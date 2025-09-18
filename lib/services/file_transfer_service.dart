import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/transfer_session.dart';
import '../models/app_settings.dart';
import 'peer_discovery_service.dart';

/// File transfer service implementation
class FileTransferService extends ChangeNotifier {
  // Transfer constants
  static const int bufferSize = 1024 * 1024; // 1MB buffer for optimal performance
  static const String textElementName = '___ZIPLINE___TEXT___'; // Text element identifier

  ServerSocket? _serverSocket;
  final Map<String, TransferSession> _activeSessions = {};
  final Map<String, TransferSession> _completedSessions = {};
  AppSettings? _settings;
  PeerDiscoveryService? _peerDiscovery;
  int _listenPort = 6442;

  // Stream controllers for session events
  final StreamController<TransferSession> _sessionStartedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionProgressController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionCompletedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionFailedController = 
      StreamController<TransferSession>.broadcast();

  // Public streams
  Stream<TransferSession> get onSessionStarted => _sessionStartedController.stream;
  Stream<TransferSession> get onSessionProgress => _sessionProgressController.stream;
  Stream<TransferSession> get onSessionCompleted => _sessionCompletedController.stream;
  Stream<TransferSession> get onSessionFailed => _sessionFailedController.stream;

  // Public getters
  Map<String, TransferSession> get activeSessions => Map.unmodifiable(_activeSessions);
  Map<String, TransferSession> get completedSessions => Map.unmodifiable(_completedSessions);
  int get historyCount => _completedSessions.length;

  // Clear all history
  void clearHistory() {
    _completedSessions.clear();
    notifyListeners();
  }

  // Cancel transfer
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

  // Initialize method (compatibility)
  Future<void> initialize() async {
    // Initialize service
    print('📡 Zipline service initialized');
  }

  // Check port availability (compatibility) 
  Future<Map<String, dynamic>> checkPortAvailability(int port) async {
    try {
      final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await serverSocket.close();
      return {
        'available': true,
        'conflictingApp': null,
      };
    } catch (e) {
      return {
        'available': false,
        'conflictingApp': 'Unknown application',
      };
    }
  }

  // Send text method (compatibility)
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

  // Get network diagnostics (compatibility)
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
  }

  // Start server
  Future<bool> startServer({int? port}) async {
    try {
      if (port != null) _listenPort = port;
      
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _listenPort);
      _serverSocket!.listen(_onIncomingConnection);
      
      print('✅ File transfer server started successfully on port $_listenPort');
      print('📡 Server listening on all interfaces (0.0.0.0:$_listenPort)');
      return true;
    } catch (e) {
      print('❌ Failed to start server on port $_listenPort: $e');
      return false;
    }
  }

  // Stop server  
  void stopServer() {
    _serverSocket?.close();
    _serverSocket = null;
    print('📡 File transfer server stopped');
  }

  // Send files with proper directory handling
  Future<bool> sendFiles(Peer peer, List<TransferItem> items) async {
    try {
      // Process items for transfer
      final processedItems = <TransferItem>[];
      int totalSize = 0;
      
      for (final item in items) {
        print('🔍 SENDER: Processing input item: ${item.name} (${item.type}) at ${item.path}');
        if (item.type == TransferType.file || item.type == TransferType.folder) {
          // Process directory or file
          final result = await _processTransferPath(item.path!, processedItems);
          totalSize += result; // Add size returned from processing
        } else if (item.type == TransferType.text) {
          processedItems.add(item);
          totalSize += utf8.encode(item.textContent!).length;
        }
      }
      
      print('🔍 SENDER: Final processed items count: ${processedItems.length}');
      for (int i = 0; i < processedItems.length; i++) {
        final item = processedItems[i];
        print('🔍 SENDER: Item $i: "${item.name}" (${item.type}, ${_formatBytes(item.size)})');
      }

      final session = TransferSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        peer: peer,
        items: processedItems, // Use processed items with directories
        totalSize: totalSize,
        totalFiles: processedItems.length,
        direction: TransferDirection.sending,
        status: TransferStatus.pending,
        startedAt: DateTime.now(),
        transferredSize: 0,
      );

      _activeSessions[session.id] = session;
      _sessionStartedController.add(session);
      notifyListeners();

      await _performTransferSend(session);
      return true;
    } catch (e) {
      print('Send failed: $e');
      return false;
    }
  }

  // Transfer: Process path like FileData::processDir with relative paths  
  Future<int> _processTransferPath(String fullPath, List<TransferItem> list, [String? relPath]) async {
    int totalSize = 0;
    
    // Transfer: First call uses filename only, recursive calls build relative path
    relPath ??= path.basename(fullPath);
    
    // Transfer: Use FileStat like QFileInfo to handle both files and directories safely
    final FileStat stat;
    try {
      stat = await FileStat.stat(fullPath);
    } catch (e) {
      throw Exception('Cannot read $fullPath');
    }
    
    if (stat.type == FileSystemEntityType.directory) {
      // Transfer: Directory processing - append with size -1 and relative path
      list.add(TransferItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: TransferType.folder,
        path: fullPath,
        name: relPath, // Use relative path
        size: -1, // Transfer: Directories have size -1
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
      ));
      
      print('📁 Transfer: Processing directory: $relPath');
      
      // Transfer: Recursive processing like QDir().entryList()
      try {
        final dirInfo = Directory(fullPath);
        await for (final entity in dirInfo.list(recursive: false, followLinks: false)) {
          final entryName = path.basename(entity.path);
          // Transfer: Build relative path like "relPath + "/" + entry" (always use forward slash)
          final childRelPath = relPath + "/" + entryName;
          print('📁 Transfer: Processing child "$entryName" with relPath: "$childRelPath"');
          final childSize = await _processTransferPath(entity.path, list, childRelPath);
          totalSize += childSize; // Accumulate child sizes (directories contribute 0)
        }
      } catch (e) {
        print('Error processing directory $fullPath: $e');
      }
    } else if (stat.type == FileSystemEntityType.file) {
      // Transfer: File processing - append with actual size and relative path
      final fileSize = stat.size;
      
      print('📄 Transfer: Processing file with relPath: "$relPath"');
      
      list.add(TransferItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: TransferType.file,
        path: fullPath,
        name: relPath, // Use relative path  
        size: fileSize,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
      ));
      
      totalSize = fileSize; // File contributes its size
      print('📄 Transfer: Added file item: $relPath (${_formatBytes(fileSize)})');
    }
    
    return totalSize; // Return accumulated size
  }

  // Transfer: Send files using sender.cpp methodology
  Future<void> _performTransferSend(TransferSession session) async {
    Socket? socket;
    
    try {
      print('📤 Transfer: Attempting connection to ${session.peer.address}:${session.peer.port}');
      print('📤 Transfer: Peer info - Name: ${session.peer.name}, Platform: ${session.peer.platform}');
      
      // Transfer: Find the best local interface to reach this peer
      final localInterface = await _findBestLocalInterface(session.peer.address);
      
      // Transfer: Connect like sender.cpp - socket->connectToHost(dest, port)
      if (localInterface != null) {
        print('📤 Transfer: Binding to local interface: $localInterface');
        socket = await Socket.connect(
          session.peer.address, 
          session.peer.port,
          sourceAddress: InternetAddress(localInterface),
        );
      } else {
        print('📤 Transfer: Using default routing');
        socket = await Socket.connect(session.peer.address, session.peer.port);
      }
      
      socket.setOption(SocketOption.tcpNoDelay, true);
      
      final updatedSession = session.copyWith(status: TransferStatus.inProgress);
      _activeSessions[session.id] = updatedSession;
      _sessionProgressController.add(updatedSession);

      // Transfer PHASE 1: Send total elements count
      final totalElements = session.items.length;
      socket.add(_int64ToBytes(totalElements));
      
      // Transfer PHASE 2: Send total size  
      socket.add(_int64ToBytes(session.totalSize));
      
      int totalBytesSent = 0;
      
      // Transfer PHASE 3: Send each element
      for (int i = 0; i < session.items.length; i++) {
        final item = session.items[i];
        
        print('📤 SENDER: Sending element "${item.name}" (${item.type})');
        
        if (item.type == TransferType.text) {
          totalBytesSent += await _sendTextElement(socket, item.textContent!, session, totalBytesSent);
        } else if (item.type == TransferType.file) {
          totalBytesSent += await _sendFileElement(socket, item.path!, item.name, session, totalBytesSent);
        } else if (item.type == TransferType.folder) {
          // Transfer: Send directory like FileData with size -1
          totalBytesSent += await _sendDirectoryElement(socket, item.path!, item.name, session, totalBytesSent);
        }
        
        // Transfer: Small delay to prevent buffer overflow (simulate bytesToWrite check)
        await Future.delayed(Duration(microseconds: 100));
      }
      
      // Transfer: Wait for all data to be sent
      await socket.flush();
      
      final completedSession = session.copyWith(
        status: TransferStatus.completed,
        completedAt: DateTime.now(),
        transferredSize: session.totalSize,
        completedFiles: session.items.length,
      );
      
      _sessionCompletedController.add(completedSession);
      _moveToCompleted(completedSession);

    } catch (e) {
      print('Transfer send failed: $e');
      
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

  // Transfer: Send file element with buffer control and proper progress
  Future<int> _sendFileElement(Socket socket, String filePath, String elementName, TransferSession session, int totalBytesSent) async {
    final file = File(filePath);
    
    // Transfer: Use FileStat like QFileInfo for safer size reading
    final stat = await FileStat.stat(filePath);
    final fileSize = stat.size;
    
    print('📁 Transfer: Sending file element: "$elementName" (${_formatBytes(fileSize)})');
    
    // Transfer: Send element name + null terminator + size (use elementName, not filename!)
    final nameBytes = utf8.encode(elementName);
    socket.add(nameBytes);
    socket.add([0]); // null terminator
    socket.add(_int64ToBytes(fileSize));
    
    // Transfer: Send file data in 1MB chunks with buffer control
    int fileBytesRead = 0;
    final fileHandle = await file.open();
    
    try {
      while (fileBytesRead < fileSize) {
        // Transfer: Read up to 1MB at a time
        final chunkSize = (fileSize - fileBytesRead).clamp(0, bufferSize);
        final chunk = await fileHandle.read(chunkSize);
        
        if (chunk.isEmpty) break;
        
        // Transfer: Write data first
        socket.add(chunk);
        fileBytesRead += chunk.length;
        totalBytesSent += chunk.length;
        
        // Transfer: Flush to actually send data to network
        await socket.flush();
        
        // Transfer: Update progress AFTER data is actually sent (like original)
        final progressSession = _activeSessions[session.id];
        if (progressSession != null) {
          final updated = progressSession.copyWith(
            transferredSize: totalBytesSent,
          );
          _activeSessions[session.id] = updated;
          _sessionProgressController.add(updated);
          notifyListeners();
        }
        
        // Transfer: Small delay after each chunk to allow network transmission
        await Future.delayed(Duration(milliseconds: 10));
      }
    } finally {
      await fileHandle.close();
    }
    
    return fileBytesRead;
  }

  // Transfer: Send text element with buffer control
  Future<int> _sendTextElement(Socket socket, String text, TransferSession session, int totalBytesSent) async {
    final textBytes = utf8.encode(text);
    
    // Transfer: Send text element name + null terminator + size
    final nameBytes = utf8.encode(textElementName);
    socket.add(nameBytes);
    socket.add([0]); // null terminator  
    socket.add(_int64ToBytes(textBytes.length));
    
    // Transfer: Send text data with proper progress timing
    socket.add(textBytes);
    await socket.flush(); // Transfer: Flush to actually send
    
    // Transfer: Update progress AFTER data is sent
    totalBytesSent += textBytes.length;
    final progressSession = _activeSessions[session.id];
    if (progressSession != null) {
      final updated = progressSession.copyWith(
        transferredSize: totalBytesSent,
      );
      _activeSessions[session.id] = updated;
      _sessionProgressController.add(updated);
      notifyListeners();
    }
    
    return textBytes.length;
  }

  // Transfer: Send directory element (like FileData with size -1)
  Future<int> _sendDirectoryElement(Socket socket, String dirPath, String elementName, TransferSession session, int totalBytesSent) async {
    print('📁 Transfer: Sending directory element: "$elementName"');
    
    // Transfer: Send element name + null terminator + size (-1 for directories)
    final nameBytes = utf8.encode(elementName);
    socket.add(nameBytes);
    socket.add([0]); // null terminator
    socket.add(_int64ToBytes(-1)); // Transfer: Directory size is -1
    
    // No data for directories
    await socket.flush();
    
    // Update progress (directories don't add to transferred bytes, just element count)
    final progressSession = _activeSessions[session.id];
    if (progressSession != null) {
      final updated = progressSession.copyWith(
        transferredSize: totalBytesSent, // No bytes for directory
      );
      _activeSessions[session.id] = updated;
      _sessionProgressController.add(updated);
      notifyListeners();
    }
    
    return 0; // Transfer: Directories contribute 0 bytes to transfer
  }

  // Transfer RECEIVING METHOD
  void _onIncomingConnection(Socket socket) {
    print('Incoming connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    
    // Transfer: Configure socket
    socket.setOption(SocketOption.tcpNoDelay, true);
    
    _handleTransferReceive(socket);
  }

  // Transfer RECEIVE - Streaming with immediate processing
  Future<void> _handleTransferReceive(Socket socket) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final senderAddress = socket.remoteAddress.address;
    
    print('📥 Transfer: Incoming transfer from $senderAddress:${socket.remotePort}');
    
    // Transfer VARIABLES - Match original receiver.cpp exactly
    int recvStatus = 0; // STS_RECEIVESIZE, STS_RECEIVETEXT, STS_RECEIVEFILE
    int currentElements = 0;
    int totalElements = 0;
    int totalSize = 0;
    int totalReceivedData = 0;
    
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
                print('📋 Transfer: Expecting $totalElements elements');
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
                  items: [],
                  totalSize: totalSize,
                  totalFiles: totalElements,
                  direction: TransferDirection.receiving,
                  status: TransferStatus.inProgress,
                  startedAt: DateTime.now(),
                  transferredSize: 0,
                );
                
                _activeSessions[sessionId] = session;
                _sessionStartedController.add(session);
                notifyListeners();
                
                print('📋 Transfer: Receiving ${_formatBytes(totalSize)} from ${senderPeer.name}');
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
                  print('📄 Transfer: Element: ${currentFileName == textElementName ? "Text snippet" : currentFileName}');
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
                  await _createDirectory(currentFileName);
                  currentElements++; // Like sessionElementsReceived++
                  
                  print('📁 Transfer: Directory created: $currentFileName ($currentElements/$totalElements)');
                  
                  // Transfer: Update progress for directories (like sessionElementsReceived++)
                  if (session != null) {
                    final updatedSession = session!.copyWith(
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
                    // Transfer: All elements received - endSession()
                    print('📋 Transfer: All elements received, completing session');
                    final completedSession = session!.copyWith(
                      status: TransferStatus.completed,
                      completedAt: DateTime.now(),
                      completedFiles: currentElements,
                      transferredSize: totalReceivedData,
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
                  final file = await _createFileForTransfer(currentFileName);
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
                
                // Transfer: Write immediately like original
                if (currentFileName == textElementName) {
                  // Text element - could accumulate for processing
                } else {
                  // File element - write directly to disk
                  await currentFile!.writeFrom(elementData);
                }
                
                currentFileBytesReceived += bytesToProcess;
                totalReceivedData += bytesToProcess;
                
                // Transfer: Update progress frequently like original  
                if (session != null) {
                  final updated = session.copyWith(transferredSize: totalReceivedData);
                  _activeSessions[sessionId] = updated;
                  session = updated;
                  _sessionProgressController.add(session);
                  notifyListeners();
                }
                
                // Element complete?
                if (currentFileBytesReceived >= currentFileSize) {
                  if (currentFile != null) {
                    await currentFile!.close();
                    currentFile = null;
                  }
                  
                  currentElements++;
                  if (currentElements < totalElements) {
                    recvStatus = 2; // Next element name
                  } else {
                    // All elements received - complete
                    final completedSession = session!.copyWith(
                      status: TransferStatus.completed,
                      completedAt: DateTime.now(),
                      completedFiles: currentElements,
                      transferredSize: totalReceivedData,
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
      print('❌ Transfer receive error: $e');
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

  // Helper methods
  Future<File> _createFileForTransfer(String fileName) async {
    if (_settings?.downloadDirectory == null) {
      throw Exception('Download directory not set');
    }
    
    print('📄 Transfer: Creating file with path: "$fileName"');
    
    // Transfer: Handle file path like original receiver.cpp
    final index = fileName.lastIndexOf('/');
    String filePath;
    
    if (index >= 0) {
      // File has parent directories - like "4kw1/image.jpg"
      final dirPath = fileName.substring(0, index); // "4kw1"
      final fileNamePart = fileName.substring(index); // "/image.jpg"
      
      // Convert to platform-specific path
      final normalizedDirPath = dirPath.replaceAll('/', Platform.pathSeparator);
      final fullDirPath = path.join(_settings!.downloadDirectory, normalizedDirPath);
      
      // Transfer: Create parent directories first
      final dir = Directory(fullDirPath);
      await dir.create(recursive: true);
      print('📁 Transfer: Created parent directory: $fullDirPath');
      
      // Build final file path
      filePath = fullDirPath + fileNamePart.replaceAll('/', Platform.pathSeparator);
    } else {
      // File with no parent directories
      filePath = path.join(_settings!.downloadDirectory, fileName);
    }
    
    print('📄 Transfer: Final file path: $filePath');
    final file = File(filePath);
    
    // Create empty file
    await file.create();
    return file;
  }

  Future<void> _createDirectory(String dirName) async {
    if (_settings?.downloadDirectory == null) {
      throw Exception('Download directory not set');
    }
    
    print('📁 Transfer: Creating directory with path: "$dirName"');
    
    // Transfer: Convert forward slashes to platform-specific separators  
    final normalizedDirName = dirName.replaceAll('/', Platform.pathSeparator);
    final dirPath = path.join(_settings!.downloadDirectory, normalizedDirName);
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    print('📁 Transfer: Created directory: "$dirName" -> "$dirPath"');
  }

  Peer _identifyPeerFromAddress(String address, int port) {
    // Try to find peer from discovery
    if (_peerDiscovery != null) {
      final discoveredPeers = _peerDiscovery!.discoveredPeers;
      for (final peer in discoveredPeers) {
        if (peer.address == address) {
          return peer;
        }
      }
    }
    
    // Return unknown peer if not found
    return Peer(
      id: 'unknown_$address',
      name: 'Unknown',
      signature: 'Unknown at $address',
      address: address,
      port: port,
      platform: 'Unknown',
    );
  }

  void _moveToCompleted(TransferSession session) {
    _activeSessions.remove(session.id);
    _completedSessions[session.id] = session;
    notifyListeners();
  }

  // Transfer: Utility methods
  List<int> _int64ToBytes(int value) {
    final buffer = Uint8List(8);
    final byteData = ByteData.view(buffer.buffer);
    byteData.setInt64(0, value, Endian.little);
    return buffer;
  }

  int _bytesToInt64(List<int> bytes) {
    if (bytes.length < 8) {
      // Pad with zeros if needed
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // Transfer: Find best local interface to reach peer (like system routing)
  Future<String?> _findBestLocalInterface(String peerAddress) async {
    try {
      final peerIP = InternetAddress(peerAddress);
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );

      // Transfer: Find interface on same subnet as peer
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          
          // Check if peer is on same subnet (simple /24 check)
          if (_isOnSameSubnet(addr.address, peerAddress)) {
            print('📤 Transfer: Found matching interface ${addr.address} for peer $peerAddress');
            return addr.address;
          }
        }
      }
      
      // If no specific match, let system handle routing
      return null;
    } catch (e) {
      print('Error finding local interface: $e');
      return null;
    }
  }

  // Transfer: Check if two IPs are on same subnet (like network routing)
  bool _isOnSameSubnet(String localIP, String peerIP) {
    try {
      final localParts = localIP.split('.').map(int.parse).toList();
      final peerParts = peerIP.split('.').map(int.parse).toList();
      
      if (localParts.length != 4 || peerParts.length != 4) return false;
      
      // Check for same /24 subnet (first 3 octets match)
      return localParts[0] == peerParts[0] && 
             localParts[1] == peerParts[1] && 
             localParts[2] == peerParts[2];
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    stopServer();
    _sessionStartedController.close();
    _sessionProgressController.close();
    _sessionCompletedController.close();
    _sessionFailedController.close();
  }
}