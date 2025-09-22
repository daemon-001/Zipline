import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/transfer_session.dart';
import '../utils/speed_calculator.dart';
import '../models/app_settings.dart';
import 'peer_discovery_service.dart';
import 'network_utility.dart';

/// File transfer service implementation
class FileTransferService extends ChangeNotifier {
  static const int bufferSize = 1024 * 1024;
  static const int maxSocketBufferSize = 1024 * 1024;
  static const int progressUpdateInterval = 256 * 1024; 
  static const String textElementName = '___ZIPLINE___TEXT___';
  static const String _historyKey = 'zipline_transfer_history';

  ServerSocket? _serverSocket;
  final Map<String, TransferSession> _activeSessions = {};
  final Map<String, TransferSession> _completedSessions = {};
  
  final Map<String, TransferSession> _pendingRequests = {};
  final Map<String, Completer<bool>> _transferRequestCompleters = {};
  
  final Map<String, SpeedCalculator> _speedCalculators = {};
  
  final Map<String, Map<String, String>> _sessionPathMappings = {};
  
  final Map<String, String> _sessionSaveLocations = {};
  
  final Map<String, String> _senderAddressToTransferId = {};
  
  AppSettings? _settings;
  PeerDiscoveryService? _peerDiscovery;
  int _listenPort = 6442;
  SharedPreferences? _prefs;

  final StreamController<TransferSession> _sessionStartedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionProgressController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionCompletedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionFailedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<String> _transferRequestRejectedController = 
      StreamController<String>.broadcast();

  Stream<TransferSession> get onSessionStarted => _sessionStartedController.stream;
  Stream<TransferSession> get onSessionProgress => _sessionProgressController.stream;
  Stream<TransferSession> get onSessionCompleted => _sessionCompletedController.stream;
  Stream<TransferSession> get onSessionFailed => _sessionFailedController.stream;
  Stream<String> get onTransferRequestRejected => _transferRequestRejectedController.stream;

  Map<String, TransferSession> get activeSessions => Map.unmodifiable(_activeSessions);
  Map<String, TransferSession> get completedSessions => Map.unmodifiable(_completedSessions);
  int get historyCount => _completedSessions.length;

  void clearHistory() async {
    _completedSessions.clear();
    await _saveHistory();
    notifyListeners();
  }

  void cancelTransfer(String sessionId) {
    final session = _activeSessions[sessionId];
    if (session != null) {
      final cancelledSession = session.copyWith(
        status: TransferStatus.cancelled,
        completedAt: DateTime.now(),
      );
      _sessionFailedController.add(cancelledSession);
      _moveToCompleted(cancelledSession);
    }
  }

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadHistory();
    } catch (e) {
    }
  }
  
  void registerIncomingTransfer({
    required String transferId,
    required String senderAddress,
    String? customSaveLocation,
  }) {
    _senderAddressToTransferId[senderAddress] = transferId;
    if (customSaveLocation != null) {
      _sessionSaveLocations[transferId] = customSaveLocation;
    }
  }

  Future<Map<String, dynamic>> checkPortAvailability(int port) async {
    try {
      final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await serverSocket.close();
      return {
        'available': true,
        'conflictingApp': null,
      };
    } catch (e) {
      final conflictingApp = await NetworkUtility.getPortUsage(port);
      return {
        'available': false,
        'conflictingApp': conflictingApp ?? 'Unknown application',
      };
    }
  }

  Future<bool> sendText(Peer peer, String text) async {
    final textItem = TransferItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: TransferType.text,
      name: 'Text snippet',
      textContent: text,
      createdAt: DateTime.now(),
      size: utf8.encode(text).length,
      status: TransferStatus.pending,
    );
    
    return await sendFiles(peer, [textItem]);
  }

  Map<String, dynamic> getNetworkDiagnostics() {
    return {
      'service': 'Zipline File Transfer',
      'active_sessions': _activeSessions.length,
      'completed_sessions': _completedSessions.length,
      'server_running': _serverSocket != null,
      'listen_port': _listenPort,
    };
  }

  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  void setPeerDiscovery(PeerDiscoveryService peerDiscovery) {
    _peerDiscovery = peerDiscovery;
    
    _peerDiscovery!.onTransferResponse.listen((responseData) {
      final transferId = responseData['transferId'] as String?;
      final responseType = responseData['responseType'] as String?;
      
      if (transferId != null) {
        final completer = _transferRequestCompleters.remove(transferId);
        if (completer != null && !completer.isCompleted) {
          if (responseType == 'accept') {
            final saveLocation = responseData['data'] as String?;
            if (saveLocation != null && _pendingRequests.containsKey(transferId)) {
              _sessionSaveLocations[transferId] = saveLocation;
            }
            completer.complete(true);
          } else {
            final reason = responseData['data'] as String? ?? 'Transfer declined';
            _transferRequestRejectedController.add(reason);
            completer.complete(false);
          }
        }
      }
    });
  }

  Future<bool> startServer({int? port}) async {
    try {
      if (port != null) _listenPort = port;
      
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _listenPort);
      _serverSocket!.listen(_onIncomingConnection);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  void stopServer() {
    _serverSocket?.close();
    _serverSocket = null;
  }

  Future<bool> sendFiles(Peer peer, List<TransferItem> items) async {
    try {
      if (items.isEmpty) return false;
      
      final processedItems = <TransferItem>[];
      int totalSize = 0;
      
      for (final item in items) {
        if (item.type == TransferType.file || item.type == TransferType.folder) {
          if (item.path == null || item.path!.isEmpty) continue;
          final result = await _processTransferPath(item.path!, processedItems);
          totalSize += result;
        } else if (item.type == TransferType.text) {
          if (item.textContent == null || item.textContent!.isEmpty) continue;
          processedItems.add(item);
          totalSize += utf8.encode(item.textContent!).length;
        }
      }
      
      if (processedItems.isEmpty) return false;

      final session = TransferSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        peer: peer,
        items: processedItems,
        totalSize: totalSize,
        totalFiles: processedItems.length,
        direction: TransferDirection.sending,
        status: TransferStatus.pending,
        startedAt: DateTime.now(),
        transferredSize: 0,
      );

      _pendingRequests[session.id] = session;
      _activeSessions[session.id] = session;
      _sessionStartedController.add(session);
      notifyListeners();

      if (_peerDiscovery != null) {
        final fileNames = processedItems.map((item) => item.name).toList();
        final description = _generateTransferDescription(processedItems);
        
        _peerDiscovery!.sendTransferRequest(
          targetPeer: peer,
          transferId: session.id,
          totalFiles: processedItems.length,
          totalSize: totalSize,
          transferDescription: description,
          fileNames: fileNames,
        );

        final completer = Completer<bool>();
        _transferRequestCompleters[session.id] = completer;
        
        Timer(const Duration(seconds: 30), () {
          if (!completer.isCompleted) {
            _transferRequestCompleters.remove(session.id);
            completer.complete(false);
          }
        });
        
        final waitingSession = session.copyWith(status: TransferStatus.waitingForAcceptance);
        _activeSessions[session.id] = waitingSession;
        _sessionProgressController.add(waitingSession);
        notifyListeners();

        final accepted = await completer.future;
        
        if (accepted) {
          await _performTransferSend(session);
          return true;
        } else {
          final rejectedSession = session.copyWith(
            status: TransferStatus.cancelled,
            error: 'Transfer request was rejected or timed out',
            completedAt: DateTime.now(),
          );
          _sessionFailedController.add(rejectedSession);
          _moveToCompleted(rejectedSession);
          return false;
        }
      } else {
        await _performTransferSend(session);
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  String _generateTransferDescription(List<TransferItem> items) {
    if (items.length == 1) {
      final item = items.first;
      if (item.type == TransferType.text) {
        return 'Text message';
      } else {
        return item.name;
      }
    } else {
      final fileCount = items.where((item) => item.type == TransferType.file).length;
      final folderCount = items.where((item) => item.type == TransferType.folder).length;
      final textCount = items.where((item) => item.type == TransferType.text).length;
      
      final parts = <String>[];
      if (fileCount > 0) parts.add('$fileCount ${fileCount == 1 ? 'file' : 'files'}');
      if (folderCount > 0) parts.add('$folderCount ${folderCount == 1 ? 'folder' : 'folders'}');
      if (textCount > 0) parts.add('$textCount text ${textCount == 1 ? 'message' : 'messages'}');
      
      return parts.join(', ');
    }
  }

  Future<int> _processTransferPath(String fullPath, List<TransferItem> list, [String? relPath]) async {
    int totalSize = 0;
    
    if (fullPath.isEmpty) return 0;
    
    relPath ??= path.basename(fullPath);
    
    final FileStat stat;
    try {
      stat = await FileStat.stat(fullPath);
    } catch (e) {
      return 0;
    }
    
    if (stat.type == FileSystemEntityType.directory) {
      list.add(TransferItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: TransferType.folder,
        path: fullPath,
        name: relPath,
        size: -1,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
      ));
      
      try {
        final dirInfo = Directory(fullPath);
        await for (final entity in dirInfo.list(recursive: false, followLinks: false)) {
          final entryName = path.basename(entity.path);
          final childRelPath = relPath + "/" + entryName;
          final childSize = await _processTransferPath(entity.path, list, childRelPath);
          totalSize += childSize;
        }
      } catch (e) {
      }
    } else if (stat.type == FileSystemEntityType.file) {
      final fileSize = stat.size;
      
      list.add(TransferItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: TransferType.file,
        path: fullPath,
        name: relPath,  
        size: fileSize,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
      ));
      
      totalSize = fileSize;
    }
    
    return totalSize;
  }

  Future<void> _performTransferSend(TransferSession session) async {
    Socket? socket;
    
    try {
      if (session.peer.address.isEmpty || session.peer.port <= 0) {
        throw Exception('Invalid peer address or port');
      }
      
      final localInterface = await _findBestLocalInterface(session.peer.address);
      
      try {
        if (localInterface != null) {
          socket = await Socket.connect(
            session.peer.address, 
            session.peer.port,
            sourceAddress: InternetAddress(localInterface),
          ).timeout(const Duration(seconds: 10));
        } else {
          socket = await Socket.connect(
            session.peer.address, 
            session.peer.port,
          ).timeout(const Duration(seconds: 10));
        }
        
        socket.setOption(SocketOption.tcpNoDelay, true);
        try {
          socket.setRawOption(RawSocketOption.fromInt(6, 7, 2 * 1024 * 1024)); // TCP_SNDBUF - 2MB
          socket.setRawOption(RawSocketOption.fromInt(6, 8, 2 * 1024 * 1024)); // TCP_RCVBUF - 2MB
        } catch (e) {
        }
        } catch (e) {
        final failedSession = session.copyWith(
          status: TransferStatus.failed,
          error: 'Connection failed: ${e.toString()}',
        );
        _activeSessions[session.id] = failedSession;
        _sessionFailedController.add(failedSession);
          notifyListeners();
        return;
      }
      
      final updatedSession = session.copyWith(
        status: TransferStatus.inProgress,
        actualDataTransferStartedAt: DateTime.now(), // Mark when actual data transfer begins
      );
      _activeSessions[session.id] = updatedSession;
      _sessionProgressController.add(updatedSession);

      _speedCalculators[session.id] = SpeedCalculator();

      final totalElements = session.items.length;
      socket.add(_int64ToBytes(totalElements));
      
      socket.add(_int64ToBytes(session.totalSize));
      
      int totalBytesSent = 0;
      
      for (int i = 0; i < session.items.length; i++) {
        final item = session.items[i];
        
        if (item.type == TransferType.text) {
          totalBytesSent += await _sendTextElement(socket, item.textContent!, session, totalBytesSent);
        } else if (item.type == TransferType.file) {
          totalBytesSent += await _sendFileElement(socket, item.path!, item.name, session, totalBytesSent);
        } else if (item.type == TransferType.folder) {
          totalBytesSent += await _sendDirectoryElement(socket, item.path!, item.name, session, totalBytesSent);
        }
        
      }
      
      await socket.flush();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final speedCalculator = _speedCalculators[session.id];
      final finalSpeed = speedCalculator?.getAverageSpeed(
        session.actualDataTransferStartedAt ?? session.startedAt
      ) ?? 0.0;
      
      final completedSession = session.copyWith(
        status: TransferStatus.completed,
        completedAt: DateTime.now(),
        transferredSize: session.totalSize,
        completedFiles: session.items.length,
        currentSpeed: finalSpeed,
      );
      
      _sessionCompletedController.add(completedSession);
      _moveToCompleted(completedSession);

    } catch (e) {
      final failedSession = session.copyWith(
        status: TransferStatus.failed,
        error: e.toString(),
        completedAt: DateTime.now(),
      );
      
      _sessionFailedController.add(failedSession);
      _moveToCompleted(failedSession);
    } finally {
        socket?.close();
    }
  }

  Future<int> _sendFileElement(Socket socket, String filePath, String elementName, TransferSession session, int totalBytesSent) async {
    final file = File(filePath);
    
    final stat = await FileStat.stat(filePath);
    final fileSize = stat.size;
    
    final nameBytes = utf8.encode(elementName);
    socket.add(nameBytes);
    socket.add([0]);
    socket.add(_int64ToBytes(fileSize));
    
    int fileBytesRead = 0;
    int fileBytesActuallySent = 0;
    int lastProgressUpdate = 0;
    final fileHandle = await file.open();
    
    try {
      while (fileBytesRead < fileSize) {
        await _implementFlowControl(socket, totalBytesSent);
        
        final chunkSize = (fileSize - fileBytesRead).clamp(0, bufferSize);
        final chunk = await fileHandle.read(chunkSize);
        
        if (chunk.isEmpty) break;
        
        socket.add(chunk);
        fileBytesRead += chunk.length;
        
        await socket.flush();
        fileBytesActuallySent = fileBytesRead;
        totalBytesSent += chunk.length;
        
        if (fileBytesActuallySent - lastProgressUpdate >= progressUpdateInterval || 
            fileBytesRead >= fileSize) {
          final progressSession = _activeSessions[session.id];
          if (progressSession != null) {
            final safeTransferredSize = totalBytesSent.clamp(0, session.totalSize);
            final now = DateTime.now();
            
            final speedCalculator = _speedCalculators[session.id];
            if (speedCalculator != null) {
              if (lastProgressUpdate == 0) {
                speedCalculator.initializeWithProgress(safeTransferredSize, now);
              } else {
                speedCalculator.recordProgress(safeTransferredSize, now);
              }
              
              final currentSpeed = speedCalculator.getCurrentSpeed(
                progressSession.actualDataTransferStartedAt ?? progressSession.startedAt
              );
              
              final updated = progressSession.copyWith(
                transferredSize: safeTransferredSize,
                currentSpeed: currentSpeed,
              );
              _activeSessions[session.id] = updated;
              _sessionProgressController.add(updated);
              notifyListeners();
            }
            lastProgressUpdate = fileBytesActuallySent;
          }
        }
      }
      
      final progressSession = _activeSessions[session.id];
      if (progressSession != null) {
        final safeTransferredSize = totalBytesSent.clamp(0, session.totalSize);
        final updated = progressSession.copyWith(transferredSize: safeTransferredSize);
        _activeSessions[session.id] = updated;
        _sessionProgressController.add(updated);
        notifyListeners();
      }
      
    } finally {
      await fileHandle.close();
    }
    
    return fileBytesRead;
  }
  
  Future<void> _implementFlowControl(Socket socket, int totalBytesSent) async {
    
    if (totalBytesSent > 50 * 1024 * 1024) {
      return;
    } else if (totalBytesSent > 10 * 1024 * 1024) {
      await Future.delayed(Duration(microseconds: 100));
    } else {
      await Future.delayed(Duration(microseconds: 500));
    }
  }

  Future<int> _sendTextElement(Socket socket, String text, TransferSession session, int totalBytesSent) async {
    final textBytes = utf8.encode(text);
    
    final nameBytes = utf8.encode(textElementName);
    socket.add(nameBytes);
    socket.add([0]);  
    socket.add(_int64ToBytes(textBytes.length));
    
    socket.add(textBytes);
    await socket.flush();
    
    await Future.delayed(Duration(milliseconds: 10));
    
    totalBytesSent += textBytes.length;
    final progressSession = _activeSessions[session.id];
    if (progressSession != null) {
      final safeTransferredSize = totalBytesSent.clamp(0, session.totalSize);
      final now = DateTime.now();
      
      final speedCalculator = _speedCalculators[session.id];
      if (speedCalculator != null) {
        speedCalculator.recordProgress(safeTransferredSize, now);
        
        final currentSpeed = speedCalculator.getCurrentSpeed(
          progressSession.actualDataTransferStartedAt ?? progressSession.startedAt
        );
        
        final updated = progressSession.copyWith(
          transferredSize: safeTransferredSize,
          currentSpeed: currentSpeed,
        );
        _activeSessions[session.id] = updated;
        _sessionProgressController.add(updated);
        notifyListeners();
      }
    }
    
    return textBytes.length;
  }

  Future<int> _sendDirectoryElement(Socket socket, String dirPath, String elementName, TransferSession session, int totalBytesSent) async {
    final nameBytes = utf8.encode(elementName);
    socket.add(nameBytes);
    socket.add([0]);
    socket.add(_int64ToBytes(-1));
    
    await socket.flush();
    
    await Future.delayed(Duration(milliseconds: 5));
    
    final progressSession = _activeSessions[session.id];
    if (progressSession != null) {
      final updated = progressSession.copyWith(
        transferredSize: totalBytesSent, // No bytes for directory
      );
      _activeSessions[session.id] = updated;
      _sessionProgressController.add(updated);
      notifyListeners();
    }
    
    return 0;
  }

  // RECEIVING METHOD - Optimized for high performance
  void _onIncomingConnection(Socket socket) {
    // Configure socket for maximum performance
    socket.setOption(SocketOption.tcpNoDelay, true);
    // Set larger buffer sizes for high-speed transfers
    try {
      socket.setRawOption(RawSocketOption.fromInt(6, 7, 2 * 1024 * 1024)); // TCP_SNDBUF - 2MB
      socket.setRawOption(RawSocketOption.fromInt(6, 8, 2 * 1024 * 1024)); // TCP_RCVBUF - 2MB  
    } catch (e) {
      // Platform doesn't support buffer size configuration
    }
    
    _handleTransferReceive(socket);
  }

  // Transfer RECEIVE - Streaming with immediate processing
  Future<void> _handleTransferReceive(Socket socket) async {
    final senderAddress = socket.remoteAddress.address;
    
    // Look up the original transfer ID from the sender address
    final originalTransferId = _senderAddressToTransferId[senderAddress];
    final sessionId = originalTransferId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // Validate sender address
    if (senderAddress.isEmpty) {
      socket.close();
      return;
    }
    
    // Transfer VARIABLES - Match original receiver.cpp exactly
    int recvStatus = 0; // STS_RECEIVESIZE, STS_RECEIVETEXT, STS_RECEIVEFILE
    int currentElements = 0;
    int totalElements = 0;
    int totalSize = 0;
    int totalReceivedData = 0;
    int lastProgressUpdate = 0; // For optimized progress tracking
    
    String currentFileName = '';
    int currentFileSize = 0;
    int currentFileBytesReceived = 0;
    RandomAccessFile? currentFile;
    
    List<int> sizeBuffer = [];
    TransferSession? session;

    try {
      // Transfer: Process data stream exactly like original
      await for (final chunk in socket) {
        int chunkIndex = 0;
        
        while (chunkIndex < chunk.length) {
          switch (recvStatus) {
            case 0: // STS_RECEIVESIZE - Read total elements first
              while (chunkIndex < chunk.length && sizeBuffer.length < 8) {
                sizeBuffer.add(chunk[chunkIndex++]);
              }
              
              if (sizeBuffer.length == 8) {
                totalElements = _bytesToInt64(sizeBuffer);
                sizeBuffer.clear();
                recvStatus = 1; // Next: total size
              }
              break;
              
            case 1: // Read total size  
              while (chunkIndex < chunk.length && sizeBuffer.length < 8) {
                sizeBuffer.add(chunk[chunkIndex++]);
              }
              
              if (sizeBuffer.length == 8) {
                totalSize = _bytesToInt64(sizeBuffer);
                sizeBuffer.clear();
              
              // Create session
                final senderPeer = _identifyPeerFromAddress(senderAddress, socket.remotePort);
              session = TransferSession(
                id: sessionId,
                  peer: senderPeer,
                items: [], // Will be populated as files are received
                  totalSize: totalSize,
                  totalFiles: totalElements,
                direction: TransferDirection.receiving,
                status: TransferStatus.inProgress,
                startedAt: DateTime.now(),
                actualDataTransferStartedAt: DateTime.now(), // Data transfer starts immediately for receiver
                transferredSize: 0,
              );
              
              // Initialize speed calculator for receiving
              _speedCalculators[sessionId] = SpeedCalculator();
              
              _activeSessions[sessionId] = session;
              _sessionStartedController.add(session);
                notifyListeners();
                
                recvStatus = 2; // Next: element name
              }
              break;
              
            case 2: // Read element name (null-terminated)
              while (chunkIndex < chunk.length) {
                final byte = chunk[chunkIndex++];
                if (byte == 0) {
                  // Null terminator found - decode name
                  currentFileName = utf8.decode(sizeBuffer);
                  sizeBuffer.clear();
                  recvStatus = 3; // Next: element size
                  break;
            } else {
                  sizeBuffer.add(byte);
                }
              }
              break;
              
            case 3: // Read element size
              while (chunkIndex < chunk.length && sizeBuffer.length < 8) {
                sizeBuffer.add(chunk[chunkIndex++]);
              }
              
              if (sizeBuffer.length == 8) {
                currentFileSize = _bytesToInt64(sizeBuffer);
                sizeBuffer.clear();
                currentFileBytesReceived = 0;
                
                if (currentFileSize == -1) {
                  // Transfer: DIRECTORY - create and move to next element (like receiver.cpp)
                  await _createDirectory(currentFileName, sessionId);
                  currentElements++; // Like sessionElementsReceived++
                  
                  // Add directory to session items
                  if (session != null) {
                    final folderItem = TransferItem(
                      id: '${sessionId}_${currentElements}_folder',
                      name: currentFileName,
                      type: TransferType.folder,
                      size: 0,
                      status: TransferStatus.completed,
                      createdAt: DateTime.now(),
                    );
                    final updatedItems = List<TransferItem>.from(session!.items)..add(folderItem);
                    
                    final updatedSession = session!.copyWith(
                      items: updatedItems,
                      transferredSize: totalReceivedData,
                      completedFiles: currentElements,
                    );
                    _activeSessions[sessionId] = updatedSession;
                    _sessionProgressController.add(updatedSession);
                    notifyListeners();
                    session = updatedSession;
                  }
                  
                  // Transfer: Check if more elements remain (like original receiver.cpp)
                  if (currentElements < totalElements) {
                    recvStatus = 2; // PHASE_ELEMENT_NAME - next element
                    // Transfer: Break and continue processing next element
                    break;
                  } else {
                    // Transfer: All elements received - endSession() with 100% progress
                    final completedSession = session!.copyWith(
                        status: TransferStatus.completed,
                        completedAt: DateTime.now(),
                      completedFiles: currentElements,
                      transferredSize: session!.totalSize, // Ensure receiver shows 100% at completion
                      );
                      _sessionCompletedController.add(completedSession);
                      _moveToCompleted(completedSession);
                    return;
                  }
                } else if (currentFileName == textElementName) {
                  // TEXT ELEMENT - read directly from stream
                  recvStatus = 4; // Next: element data
              } else {
                  // FILE ELEMENT - open for writing
                  final file = await _createFileForTransfer(currentFileName, sessionId);
                  currentFile = await file.open(mode: FileMode.write);
                  recvStatus = 4; // Next: element data
                }
              }
              break;
              
            case 4: // Read element data - Transfer streaming
              final remainingInElement = currentFileSize - currentFileBytesReceived;
              final availableInChunk = chunk.length - chunkIndex;
              final bytesToProcess = remainingInElement.clamp(0, availableInChunk);
              
              if (bytesToProcess > 0) {
                final elementData = chunk.sublist(chunkIndex, chunkIndex + bytesToProcess);
                chunkIndex += bytesToProcess;
                
                // Transfer: High-performance I/O - batch writes for better performance
                if (currentFileName == textElementName) {
                  // Text element - could accumulate for processing
                } else {
                  // File element - write directly to disk (RandomAccessFile is already buffered)
                  await currentFile!.writeFrom(elementData);
                }
                
                currentFileBytesReceived += bytesToProcess;
                totalReceivedData += bytesToProcess;
                
                // Update progress with synchronized timing
                if (session != null && (totalReceivedData - lastProgressUpdate >= progressUpdateInterval || 
                    currentFileBytesReceived >= currentFileSize)) {
                  final safeTransferredSize = totalReceivedData.clamp(0, session.totalSize);
                  final now = DateTime.now();
                  
                  // Update speed calculator with proper initialization
                  final speedCalculator = _speedCalculators[sessionId];
                  if (speedCalculator != null) {
                    if (lastProgressUpdate == 0) {
                      speedCalculator.initializeWithProgress(safeTransferredSize, now);
                    } else {
                      speedCalculator.recordProgress(safeTransferredSize, now);
                    }
                    
                    final currentSpeed = speedCalculator.getCurrentSpeed(
                      session.actualDataTransferStartedAt ?? session.startedAt
                    );
                    
                    final updated = session.copyWith(
                      transferredSize: safeTransferredSize,
                      currentSpeed: currentSpeed,
                    );
                    _activeSessions[sessionId] = updated;
                    session = updated;
                    _sessionProgressController.add(session);
                    notifyListeners();
                  }
                  lastProgressUpdate = totalReceivedData;
                }
                
                // Element complete?
                if (currentFileBytesReceived >= currentFileSize) {
                  if (currentFile != null) {
                    await currentFile!.close();
                    currentFile = null;
                  }
                  
                  // Add completed element to session items
                  if (session != null) {
                    if (currentFileName == textElementName) {
                      // Add text item
                      final textItem = TransferItem(
                        id: '${sessionId}_${currentElements}_text',
                        name: 'Text message',
                        type: TransferType.text,
                        size: currentFileSize,
                        status: TransferStatus.completed,
                        createdAt: DateTime.now(),
                        textContent: '', // Could be populated if needed
                      );
                      final updatedItems = List<TransferItem>.from(session!.items)..add(textItem);
                      session = session!.copyWith(items: updatedItems);
                    } else {
                      // Add file item (directories are added when created)
                      final fileItem = TransferItem(
                        id: '${sessionId}_${currentElements}_file',
                        name: currentFileName,
                        type: TransferType.file,
                        size: currentFileSize,
                        status: TransferStatus.completed,
                        createdAt: DateTime.now(),
                      );
                      final updatedItems = List<TransferItem>.from(session!.items)..add(fileItem);
                      session = session!.copyWith(items: updatedItems);
                    }
                  }
                  
                  currentElements++;
                  if (currentElements < totalElements) {
                    recvStatus = 2; // Next element name
                  } else {
                    // All elements received - calculate final speed and complete
                    final speedCalculator = _speedCalculators[sessionId];
                    final finalSpeed = speedCalculator?.getAverageSpeed(
                      session!.actualDataTransferStartedAt ?? session!.startedAt
                    ) ?? 0.0;
                    
                    final completedSession = session!.copyWith(
                      status: TransferStatus.completed,
                      completedAt: DateTime.now(),
                      completedFiles: currentElements,
                      transferredSize: session!.totalSize, // Ensure 100% completion
                      currentSpeed: finalSpeed,
                    );
                    _sessionCompletedController.add(completedSession);
                    _moveToCompleted(completedSession);
                    return;
                  }
              }
            }
              break;
          }
        }
      }
    } catch (e) {
      if (currentFile != null) {
        await currentFile.close();
      }
        if (session != null) {
          final failedSession = session.copyWith(
            status: TransferStatus.failed,
          error: e.toString(),
            completedAt: DateTime.now(),
          );
          _sessionFailedController.add(failedSession);
          _moveToCompleted(failedSession);
      }
    } finally {
      if (currentFile != null) {
        await currentFile.close();
      }
        socket.close();
    }
  }

  /// Get a unique file path by adding (1), (2) etc. suffix if file already exists
  String _getUniqueFilePath(String originalPath) {
    final file = File(originalPath);
    if (!file.existsSync()) {
      return originalPath;
    }

    final dir = path.dirname(originalPath);
    final fileName = path.basenameWithoutExtension(originalPath);
    final extension = path.extension(originalPath);

    int counter = 1;
    String uniquePath;
    
    do {
      final newFileName = '$fileName ($counter)$extension';
      uniquePath = path.join(dir, newFileName);
      counter++;
    } while (File(uniquePath).existsSync());

    return uniquePath;
  }

  /// Get a unique directory path by adding (1), (2) etc. suffix if directory already exists
  String _getUniqueDirectoryPath(String originalPath) {
    final dir = Directory(originalPath);
    if (!dir.existsSync()) {
      return originalPath;
    }

    final parentDir = path.dirname(originalPath);
    final dirName = path.basename(originalPath);

    int counter = 1;
    String uniquePath;
    
    do {
      final newDirName = '$dirName ($counter)';
      uniquePath = path.join(parentDir, newDirName);
      counter++;
    } while (Directory(uniquePath).existsSync());

    return uniquePath;
  }

  /// Get the effective download directory for a session
  String _getDownloadDirectoryForSession(String sessionId) {
    final customLocation = _sessionSaveLocations[sessionId];
    if (customLocation != null) {
      return customLocation;
    }
    
    return _settings?.downloadDirectory ?? '';
  }

  Future<File> _createFileForTransfer(String fileName, String sessionId) async {
    final downloadDirectory = _getDownloadDirectoryForSession(sessionId);
    if (downloadDirectory.isEmpty) {
      throw Exception('Download directory not set');
    }
    
    _sessionPathMappings[sessionId] ??= <String, String>{};
    
    final index = fileName.lastIndexOf('/');
    String filePath;
    
    if (index >= 0) {
      final dirPath = fileName.substring(0, index);
      final fileNamePart = fileName.substring(index + 1);
      
      final normalizedDirPath = dirPath.replaceAll('/', Platform.pathSeparator);
      final originalFullDirPath = path.join(downloadDirectory, normalizedDirPath);
      
      String mappedDirPath;
      if (_sessionPathMappings[sessionId]!.containsKey(dirPath)) {
        mappedDirPath = _sessionPathMappings[sessionId]![dirPath]!;
      } else {
        mappedDirPath = _getUniqueDirectoryPath(originalFullDirPath);
        _sessionPathMappings[sessionId]![dirPath] = mappedDirPath;
        
        final dir = Directory(mappedDirPath);
        await dir.create(recursive: true);
      }
      
      filePath = path.join(mappedDirPath, fileNamePart);
    } else {
      filePath = path.join(downloadDirectory, fileName);
    }

    filePath = _getUniqueFilePath(filePath);
    
    final file = File(filePath);
    
    await file.create();
    return file;
  }

  Future<void> _createDirectory(String dirName, String sessionId) async {
    final downloadDirectory = _getDownloadDirectoryForSession(sessionId);
    if (downloadDirectory.isEmpty) {
      throw Exception('Download directory not set');
    }
    
    _sessionPathMappings[sessionId] ??= <String, String>{};
    
    final normalizedDirName = dirName.replaceAll('/', Platform.pathSeparator);
    final originalDirPath = path.join(downloadDirectory, normalizedDirName);
    
    String uniqueDirPath;
    if (_sessionPathMappings[sessionId]!.containsKey(dirName)) {
      uniqueDirPath = _sessionPathMappings[sessionId]![dirName]!;
    } else {
      uniqueDirPath = _getUniqueDirectoryPath(originalDirPath);
      _sessionPathMappings[sessionId]![dirName] = uniqueDirPath;
    }
    
    final dir = Directory(uniqueDirPath);
    await dir.create(recursive: true);
  }

  Peer _identifyPeerFromAddress(String address, int port) {
    if (_peerDiscovery != null) {
      final discoveredPeers = _peerDiscovery!.discoveredPeers;
      for (final peer in discoveredPeers) {
        if (peer.address == address) {
          return peer;
        }
      }
    }
    
    return Peer(
      id: 'unknown_$address',
      name: 'Unknown',
      signature: 'Unknown at $address',
      address: address,
      port: port,
      platform: 'Unknown',
    );
  }

  void _moveToCompleted(TransferSession session) async {
    _activeSessions.remove(session.id);
    _pendingRequests.remove(session.id);
    _transferRequestCompleters.remove(session.id);
    _speedCalculators.remove(session.id);
    _sessionPathMappings.remove(session.id);
    _sessionSaveLocations.remove(session.id);
    
    _senderAddressToTransferId.removeWhere((address, transferId) => transferId == session.id);
    
    _completedSessions[session.id] = session;
    await _saveHistory();
    notifyListeners();
  }

  List<int> _int64ToBytes(int value) {
    final buffer = Uint8List(8);
    final byteData = ByteData.view(buffer.buffer);
    byteData.setInt64(0, value, Endian.little);
    return buffer;
  }

  int _bytesToInt64(List<int> bytes) {
    if (bytes.length < 8) {
      final paddedBytes = List<int>.filled(8, 0);
      for (int i = 0; i < bytes.length; i++) {
        paddedBytes[i] = bytes[i];
      }
      bytes = paddedBytes;
    }
    
    final buffer = Uint8List.fromList(bytes.take(8).toList());
    final byteData = ByteData.view(buffer.buffer);
    return byteData.getInt64(0, Endian.little);
  }


  Future<String?> _findBestLocalInterface(String peerAddress) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          
          if (_isOnSameSubnet(addr.address, peerAddress)) {
            return addr.address;
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  bool _isOnSameSubnet(String localIP, String peerIP) {
    try {
      final localParts = localIP.split('.').map(int.parse).toList();
      final peerParts = peerIP.split('.').map(int.parse).toList();
      
      if (localParts.length != 4 || peerParts.length != 4) return false;
      
      return localParts[0] == peerParts[0] && 
             localParts[1] == peerParts[1] && 
             localParts[2] == peerParts[2];
    } catch (e) {
      return false;
    }
  }


  Future<void> _loadHistory() async {
    if (_prefs == null) return;
    
    try {
      final historyJson = _prefs!.getString(_historyKey);
      if (historyJson != null && historyJson.isNotEmpty) {
        final historyList = jsonDecode(historyJson) as List<dynamic>;
        _completedSessions.clear();
        
        for (final sessionData in historyList) {
          try {
            final sessionMap = sessionData as Map<String, dynamic>;
            final session = TransferSession.fromJson(sessionMap);
            _completedSessions[session.id] = session;
          } catch (e) {
            continue;
          }
        }
        
        notifyListeners();
      }
    } catch (e) {
      _completedSessions.clear();
    }
  }
  
  Future<void> _saveHistory() async {
    if (_prefs == null) return;
    
    try {
      final historyList = _completedSessions.values
          .map((session) => session.toJson())
          .toList();
      final historyJson = jsonEncode(historyList);
      await _prefs!.setString(_historyKey, historyJson);
    } catch (e) {
    }
  }

  @override
  void dispose() {
    stopServer();
    _sessionStartedController.close();
    _sessionProgressController.close();
    _sessionCompletedController.close();
    _sessionFailedController.close();
    super.dispose();
  }
}