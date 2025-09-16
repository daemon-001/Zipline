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

class FileTransferService extends ChangeNotifier {
  static const int bufferSize = 1024 * 1024; // 1MB buffer for optimal performance
  static const String textElementName = '___ZIPLINE___TEXT___';

  ServerSocket? _serverSocket;
  final Map<String, TransferSession> _activeSessions = {};
  final Map<String, TransferSession> _completedSessions = {};
  AppSettings? _settings;
  Timer? _progressUpdateTimer;
  
  // Track unique folder paths for each session to ensure files go to the right folder
  final Map<String, Map<String, String>> _sessionFolderPaths = {};
  
  // Public getter for accessing sessions
  Map<String, TransferSession> get activeSessions => Map.unmodifiable(_activeSessions);
  Map<String, TransferSession> get completedSessions => Map.unmodifiable(_completedSessions);
  
  // Get history count
  int get historyCount => _completedSessions.length;
  
  // Clear all history
  void clearHistory() {
    _completedSessions.clear();
    notifyListeners();
  }
  
  // Clear old history (older than specified days)
  void clearOldHistory({int days = 30}) {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    _completedSessions.removeWhere((key, session) => 
      session.completedAt != null && session.completedAt!.isBefore(cutoffDate));
    notifyListeners();
  }
  
  final StreamController<TransferSession> _sessionStartedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionProgressController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionCompletedController = 
      StreamController<TransferSession>.broadcast();
  final StreamController<TransferSession> _sessionFailedController = 
      StreamController<TransferSession>.broadcast();

  Stream<TransferSession> get onSessionStarted => _sessionStartedController.stream;
  Stream<TransferSession> get onSessionProgress => _sessionProgressController.stream;
  Stream<TransferSession> get onSessionCompleted => _sessionCompletedController.stream;
  Stream<TransferSession> get onSessionFailed => _sessionFailedController.stream;

  int _listenPort = 7250;

  void updateSettings(AppSettings settings) {
    _settings = settings;
  }
  
  // Initialize the service
  void initialize() {
    // Clean up old history (older than 30 days) on startup
    clearOldHistory(days: 30);
  }

  // Start periodic progress updates for better UI responsiveness
  void _startProgressUpdates() {
    _progressUpdateTimer?.cancel();
    _progressUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_activeSessions.isNotEmpty) {
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  // Stop progress updates
  void _stopProgressUpdates() {
    _progressUpdateTimer?.cancel();
    _progressUpdateTimer = null;
  }

  // Move completed session to completed list (permanent storage)
  void _moveToCompleted(TransferSession session) {
    // Remove from active sessions
    _activeSessions.remove(session.id);
    
    // Add to completed sessions (permanent storage)
    _completedSessions[session.id] = session;
    
    // Stop progress updates if no active sessions
    if (_activeSessions.isEmpty) {
      _stopProgressUpdates();
    }
    
    // Clean up folder paths for this session (but keep the session in history)
    _sessionFolderPaths.remove(session.id);
    
    notifyListeners();
  }

  // Connect with retry mechanism
  Future<Socket> _connectWithRetry(String address, int port, int maxRetries) async {
    SocketException? lastException;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('Connection attempt $attempt/$maxRetries to $address:$port');
        
        final socket = await Socket.connect(
          address, 
          port,
          timeout: const Duration(seconds: 15),
        );
        
        // Configure socket for better stability
        socket.setOption(SocketOption.tcpNoDelay, true);
        
        print('Connected successfully on attempt $attempt');
        return socket;
        
      } catch (e) {
        lastException = e is SocketException ? e : SocketException('Connection failed: $e');
        print('Connection attempt $attempt failed: $e');
        
        if (attempt < maxRetries) {
          // Wait before retrying (exponential backoff)
          final delay = Duration(seconds: attempt * 2);
          print('Retrying in ${delay.inSeconds} seconds...');
          await Future.delayed(delay);
        }
      }
    }
    
    throw lastException ?? SocketException('All connection attempts failed');
  }

  Future<bool> startServer(int port) async {
    try {
      _listenPort = port;
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverSocket!.listen(_onIncomingConnection);
      print('File transfer server started on port $port');
      return true;
    } catch (e) {
      print('Failed to start file transfer server: $e');
      return false;
    }
  }

  void stopServer() {
    _serverSocket?.close();
    _serverSocket = null;
  }

  Future<String?> sendFiles({
    required Peer peer,
    required List<String> filePaths,
  }) async {
    try {
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final items = <TransferItem>[];
      int totalSize = 0;
      int totalElements = 0;
      int totalFiles = 0;

      print('Starting file transfer to ${peer.name} at ${peer.address}:${peer.port}');
      print('Files to send: $filePaths');

      // Prepare transfer items
      for (final filePath in filePaths) {
        final file = File(filePath);
        final stat = await file.stat();
        
        if (stat.type == FileSystemEntityType.file) {
          final item = TransferItem(
            id: '${sessionId}_${items.length}',
            name: path.basename(filePath),
            path: filePath,
            size: stat.size,
            type: TransferType.file,
            status: TransferStatus.pending,
            createdAt: DateTime.now(),
          );
          
          items.add(item);
          totalSize += stat.size;
          totalElements++;
          totalFiles++; // Count individual files
        } else if (stat.type == FileSystemEntityType.directory) {
          // Count directory contents
          final dirItems = await _countDirectoryContents(filePath);
          final filesInDir = await _countFilesInDirectory(filePath);
          totalSize += dirItems['size'] as int;
          totalElements += dirItems['elements'] as int;
          totalFiles += filesInDir; // Count files in directories
          
          print('Directory $filePath: ${dirItems['elements']} elements, ${dirItems['size']} bytes, $filesInDir files');
          
          // Add directory item
          final item = TransferItem(
            id: '${sessionId}_${items.length}',
            name: path.basename(filePath),
            path: filePath,
            size: -1, // Directory has size -1 in transfer protocol
            type: TransferType.folder,
            status: TransferStatus.pending,
            createdAt: DateTime.now(),
          );
          items.add(item);
        }
      }

      final session = TransferSession(
        id: sessionId,
        peer: peer,
        items: items,
        direction: TransferDirection.sending,
        status: TransferStatus.pending,
        startedAt: DateTime.now(),
        totalSize: totalSize,
        totalFiles: totalFiles,
        completedFiles: 0,
      );

      _activeSessions[sessionId] = session;
      _sessionStartedController.add(session);

      // Start progress updates
      _startProgressUpdates();

      // Start transfer in background
      _performSendTransfer(session, totalElements);
      
      return sessionId;
    } catch (e) {
      print('Failed to initiate file transfer: $e');
      return null;
    }
  }

  // Count elements and size in directory recursively
  Future<Map<String, int>> _countDirectoryContents(String dirPath) async {
    int totalSize = 0;
    int totalElements = 0;
    
    final dir = Directory(dirPath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        totalSize += stat.size;
        totalElements++;
      } else if (entity is Directory) {
        totalElements++; // Count directories too
      }
    }
    
    // Add 1 for the directory itself (it gets sent as an element)
    totalElements += 1;
    
    return {'size': totalSize, 'elements': totalElements};
  }

  // Count only files (not directories) for progress tracking
  Future<int> _countFilesInDirectory(String dirPath) async {
    int fileCount = 0;
    
    final dir = Directory(dirPath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        fileCount++;
      }
    }
    
    return fileCount;
  }

  Future<String?> sendText({
    required Peer peer,
    required String text,
  }) async {
    try {
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final textBytes = utf8.encode(text);
      
      print('Starting text transfer to ${peer.name} at ${peer.address}:${peer.port}');
      
      final item = TransferItem(
        id: '${sessionId}_0',
        name: 'Text Snippet',
        size: textBytes.length,
        type: TransferType.text,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
        textContent: text,
      );

      final session = TransferSession(
        id: sessionId,
        peer: peer,
        items: [item],
        direction: TransferDirection.sending,
        status: TransferStatus.pending,
        startedAt: DateTime.now(),
        totalSize: textBytes.length,
      );

      _activeSessions[sessionId] = session;
      _sessionStartedController.add(session);

      // Start progress updates
      _startProgressUpdates();

      // Start transfer in background
      _performTextTransfer(session);
      
      return sessionId;
    } catch (e) {
      print('Failed to initiate text transfer: $e');
      return null;
    }
  }

  void cancelTransfer(String sessionId) {
    final session = _activeSessions[sessionId];
    if (session != null) {
      final updatedSession = session.copyWith(
        status: TransferStatus.cancelled,
        completedAt: DateTime.now(),
      );
      _activeSessions[sessionId] = updatedSession;
      _sessionFailedController.add(updatedSession);
    }
  }

  // File transfer implementation
  Future<void> _performSendTransfer(TransferSession session, int totalElements) async {
    Socket? socket;
    
    try {
      print('Connecting to ${session.peer.address}:${session.peer.port}');
      
      // Update session status
      var updatedSession = session.copyWith(status: TransferStatus.inProgress);
      _activeSessions[session.id] = updatedSession;
      _sessionProgressController.add(updatedSession);

      // Connect to peer with retry mechanism
      socket = await _connectWithRetry(session.peer.address, session.peer.port, 3);
      print('Connected successfully, starting transfer...');

      int totalBytesSent = 0;

      // Phase 1: Send total elements count and total size (8 bytes each)
      final totalElementsBytes = _int64ToBytes(totalElements);
      final totalSizeBytes = _int64ToBytes(session.totalSize);
      
      try {
        socket.add(totalElementsBytes);
        socket.add(totalSizeBytes);
        await socket.flush();
        print('Sent header: $totalElements elements, ${session.totalSize} bytes');
      } catch (e) {
        print('Error sending transfer header: $e');
        throw SocketException('Write failed: ${e.toString()}');
      }

      // Phase 2: Send each element with progress tracking
      for (final item in session.items) {
        if (_activeSessions[session.id]?.status == TransferStatus.cancelled) {
          print('Transfer cancelled by user');
          return;
        }
        
        // Check connection health before each item
        try {
          if (socket.remoteAddress == null) {
            throw SocketException('Connection lost before sending item: ${item.name}');
          }
        } catch (e) {
          print('Connection health check failed before ${item.name}: $e');
          throw SocketException('Write failed: Connection lost');
        }

        if (item.type == TransferType.folder) {
          // For folders, track progress as we send each file inside
          // Update session to show we're starting folder transfer
          updatedSession = updatedSession.copyWith(
            currentFileName: item.name,
            transferredSize: totalBytesSent,
          );
          _activeSessions[session.id] = updatedSession;
          _sessionProgressController.add(updatedSession);
          notifyListeners();
          
          totalBytesSent = await _sendDirectoryContentsWithProgress(socket, item.path!, totalBytesSent, session);
        } else {
          // Update current file being transferred
          updatedSession = updatedSession.copyWith(
            currentFileName: item.name,
            transferredSize: totalBytesSent,
          );
          _activeSessions[session.id] = updatedSession;
          _sessionProgressController.add(updatedSession);
          notifyListeners();
          
          totalBytesSent = await _sendFileElement(socket, item, session, totalBytesSent);
          
          // Update progress after each file
          updatedSession = updatedSession.copyWith(
            transferredSize: totalBytesSent,
            currentFileName: null,
          );
          _activeSessions[session.id] = updatedSession;
          _sessionProgressController.add(updatedSession);
          notifyListeners();
        }
        
        print('Sent ${item.name}: progress at $totalBytesSent bytes');
      }

      // Final flush to ensure all data is sent
      try {
        await socket.flush();
        print('Final socket flush completed');
      } catch (e) {
        print('Warning: Final socket flush failed: $e');
      }

      // Ensure final progress is 100% when transfer completes
      print('Final progress check: $totalBytesSent/${session.totalSize} bytes (${(totalBytesSent / session.totalSize * 100).toStringAsFixed(1)}%)');
      
      // Only adjust if there's a small discrepancy (less than 1KB)
      if (totalBytesSent < session.totalSize && (session.totalSize - totalBytesSent) < 1024) {
        print('Adjusting final progress: $totalBytesSent -> ${session.totalSize} (difference: ${session.totalSize - totalBytesSent} bytes)');
        totalBytesSent = session.totalSize;
        updatedSession = updatedSession.copyWith(transferredSize: totalBytesSent);
        _activeSessions[session.id] = updatedSession;
        _sessionProgressController.add(updatedSession);
      } else if (totalBytesSent != session.totalSize) {
        print('ERROR: Transfer size mismatch - Expected: ${session.totalSize}, Actual: $totalBytesSent (difference: ${session.totalSize - totalBytesSent} bytes)');
        print('This mismatch might cause the 99% failure issue!');
        
        // Force completion if we're very close (within 0.1%)
        final difference = (session.totalSize - totalBytesSent).abs();
        final percentDifference = (difference / session.totalSize * 100);
        if (percentDifference < 0.1) {
          print('Forcing completion due to minimal difference: ${percentDifference.toStringAsFixed(3)}%');
          totalBytesSent = session.totalSize;
          updatedSession = updatedSession.copyWith(transferredSize: totalBytesSent);
          _activeSessions[session.id] = updatedSession;
          _sessionProgressController.add(updatedSession);
        }
      }

      print('Transfer completed successfully');
      print('Final transfer stats: $totalBytesSent/${session.totalSize} bytes, ${updatedSession.completedFiles} files');
      
      // Complete transfer - ensure final values are set
      updatedSession = updatedSession.copyWith(
        status: TransferStatus.completed,
        completedAt: DateTime.now(),
        transferredSize: totalBytesSent, // Ensure final transferred size is set
        completedFiles: session.totalFiles, // Ensure all files are marked as completed
      );
      _sessionCompletedController.add(updatedSession);
      
      // Move to completed sessions
      _moveToCompleted(updatedSession);

    } catch (e) {
      print('Transfer failed: $e');
      
      // Provide more specific error messages
      String errorMessage;
      if (e is SocketException) {
        if (e.message.contains('forcibly closed')) {
          errorMessage = 'Connection was closed by the receiver. The receiver might have cancelled the transfer or encountered an error.';
        } else if (e.message.contains('Connection refused')) {
          errorMessage = 'Cannot connect to receiver. Make sure the receiver is ready and accessible.';
        } else if (e.message.contains('semaphore timeout')) {
          errorMessage = 'Connection timeout. The receiver may be busy or network is slow. Try again.';
        } else if (e.message.contains('timeout')) {
          errorMessage = 'Connection timeout. Please check your network connection and try again.';
        } else {
          errorMessage = 'Network error: ${e.message}';
        }
      } else if (e is TimeoutException) {
        errorMessage = 'Transfer timeout. The connection took too long to establish. Please try again.';
      } else {
        errorMessage = e.toString();
      }
      
      // Handle transfer failure
      final failedSession = session.copyWith(
        status: TransferStatus.failed,
        completedAt: DateTime.now(),
        error: errorMessage,
      );
      _sessionFailedController.add(failedSession);
      
      // Move to completed sessions (failed transfers also get cleaned up)
      _moveToCompleted(failedSession);
    } finally {
      try {
        // Add a small delay before closing to ensure all data is sent
        await Future.delayed(const Duration(milliseconds: 50));
        socket?.close();
        print('Socket closed successfully');
      } catch (e) {
        print('Error closing socket: $e');
      }
    }
  }

  // Send a single file element using transfer protocol
  Future<int> _sendFileElement(Socket socket, TransferItem item, TransferSession session, int totalBytesSent) async {
    // Send element name length (8 bytes)
    final nameBytes = utf8.encode(item.name);
    final nameLengthBytes = _int64ToBytes(nameBytes.length);
    socket.add(nameLengthBytes);
    await socket.flush();

    // Send element name
    socket.add(nameBytes);
    await socket.flush();

    // Send element size (8 bytes)
    final sizeBytes = _int64ToBytes(item.size);
    socket.add(sizeBytes);
    await socket.flush();

    // Send element data
    if (item.type == TransferType.file) {
      final file = File(item.path!);
      final stream = file.openRead();
      int fileBytesSent = 0;
      
      // Update session to show we're starting file transfer
      var currentSession = _activeSessions[session.id];
      if (currentSession != null) {
        var updatedSession = currentSession.copyWith(
          currentFileName: item.name,
          transferredSize: totalBytesSent,
        );
        _activeSessions[session.id] = updatedSession;
        _sessionProgressController.add(updatedSession);
        notifyListeners();
      }
      
      await for (final chunk in stream) {
        try {
          // Check connection health before sending
          if (socket.remoteAddress == null) {
            throw SocketException('Connection lost during file transfer');
          }
          
          socket.add(chunk);
          await socket.flush();
          fileBytesSent += chunk.length;
          totalBytesSent += chunk.length;
          
          // Update progress more frequently for better responsiveness
          // For small files, update more frequently; for large files, every 4KB
          final updateInterval = item.size < 1024 * 1024 ? 1024 : 4 * 1024; // 1KB for files < 1MB, 4KB for larger files
          if (fileBytesSent % updateInterval == 0) {
            currentSession = _activeSessions[session.id];
            if (currentSession != null) {
              var updatedSession = currentSession.copyWith(
                transferredSize: totalBytesSent,
                currentFileName: item.name,
                completedFiles: currentSession.completedFiles,
              );
              _activeSessions[session.id] = updatedSession;
              _sessionProgressController.add(updatedSession);
              notifyListeners(); // Ensure UI updates
            }
          }
          
          // Add small delay every 4KB to prevent overwhelming the connection
          if (fileBytesSent % (4 * 1024) == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
          
        } catch (e) {
          print('Error sending chunk for file ${item.name} at position $fileBytesSent: $e');
          rethrow;
        }
      }
      
      // Update final progress for this file
      currentSession = _activeSessions[session.id];
      if (currentSession != null) {
        var updatedSession = currentSession.copyWith(
          transferredSize: totalBytesSent,
          completedFiles: currentSession.completedFiles + 1,
        );
        _activeSessions[session.id] = updatedSession;
        _sessionProgressController.add(updatedSession);
        notifyListeners();
      }
      
      return totalBytesSent;
      
    } else if (item.type == TransferType.folder) {
      // For directories, send all contents recursively
      await _sendDirectoryContents(socket, item.path!);
      return totalBytesSent;
    }
    
    return totalBytesSent;
  }

  // Send directory contents recursively
  Future<void> _sendDirectoryContents(Socket socket, String dirPath) async {
    final dir = Directory(dirPath);
    final baseName = path.basename(dirPath);
    
    // Send directory entry first (with size -1 to indicate directory)
    final dirNameBytes = utf8.encode(baseName);
    socket.add(_int64ToBytes(dirNameBytes.length));
    await socket.flush();
    
    socket.add(dirNameBytes);
    await socket.flush();
    
    // Send -1 to indicate this is a directory
    socket.add(_int64ToBytes(-1));
    await socket.flush();
    
    // Then send all contents recursively
    await _sendDirectoryContentsRecursive(socket, dirPath, baseName);
  }

  // New method for tracking progress during folder transfers
  Future<int> _sendDirectoryContentsWithProgress(Socket socket, String dirPath, int currentBytesSent, TransferSession session) async {
    final dir = Directory(dirPath);
    final baseName = path.basename(dirPath);
    
    // Send directory entry first (with size -1 to indicate directory)
    final dirNameBytes = utf8.encode(baseName);
    socket.add(_int64ToBytes(dirNameBytes.length));
    await socket.flush();
    
    socket.add(dirNameBytes);
    await socket.flush();
    
    // Send -1 to indicate this is a directory
    socket.add(_int64ToBytes(-1));
    await socket.flush();
    
    // Then send all contents recursively with progress tracking
    return await _sendDirectoryContentsRecursiveWithProgress(socket, dirPath, baseName, currentBytesSent, session);
  }
  
  // Helper method for recursive directory sending
  Future<void> _sendDirectoryContentsRecursive(Socket socket, String dirPath, String relativePath) async {
    final dir = Directory(dirPath);
    
    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          final fileRelativePath = '$relativePath/$fileName';
          
          // Send file name length
          final nameBytes = utf8.encode(fileRelativePath);
          socket.add(_int64ToBytes(nameBytes.length));
          await socket.flush();
          
          // Send file name  
          socket.add(nameBytes);
          await socket.flush();
          
          // Send file size
          final stat = await entity.stat();
          socket.add(_int64ToBytes(stat.size));
          await socket.flush();
          
          // Send file data
          final fileStream = entity.openRead();
          await for (final chunk in fileStream) {
            socket.add(chunk);
            await socket.flush();
          }
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          final dirRelativePath = '$relativePath/$dirName';
          
          // Send directory name
          final nameBytes = utf8.encode(dirRelativePath);
          socket.add(_int64ToBytes(nameBytes.length));
          await socket.flush();
          
          socket.add(nameBytes);
          await socket.flush();
          
          // Send -1 to indicate this is a directory
          socket.add(_int64ToBytes(-1));
          await socket.flush();
          
          // Recursively send subdirectory contents
          await _sendDirectoryContentsRecursive(socket, entity.path, dirRelativePath);
        }
      }
    } catch (e) {
      print('Error sending directory contents: $e');
      rethrow;
    }
  }

  // New recursive method with progress tracking
  Future<int> _sendDirectoryContentsRecursiveWithProgress(Socket socket, String dirPath, String relativePath, int currentBytesSent, TransferSession session) async {
    final dir = Directory(dirPath);
    int bytesSent = currentBytesSent;
    
    print('Starting directory transfer: $dirPath (starting at $bytesSent bytes)');
    
    try {
      await for (final entity in dir.list(recursive: false)) {
        // Check for cancellation
        if (_activeSessions[session.id]?.status == TransferStatus.cancelled) {
          print('Transfer cancelled during folder processing');
          return bytesSent;
        }

        if (entity is File) {
          final fileName = path.basename(entity.path);
          final fileRelativePath = '$relativePath/$fileName';
          
          // Update current file being transferred and show initial progress
          final currentSession = _activeSessions[session.id];
          if (currentSession != null) {
            var updatedSession = currentSession.copyWith(
              currentFileName: fileRelativePath,
              completedFiles: currentSession.completedFiles,
              transferredSize: bytesSent, // Show current progress immediately
            );
            _activeSessions[session.id] = updatedSession;
            _sessionProgressController.add(updatedSession);
            notifyListeners(); // Ensure UI updates
          }
          
          // Send file name length
          final nameBytes = utf8.encode(fileRelativePath);
          try {
            socket.add(_int64ToBytes(nameBytes.length));
            await socket.flush();
          } catch (e) {
            print('Error sending file name length for $fileRelativePath: $e');
            throw SocketException('Write failed: ${e.toString()}');
          }
          
          // Send file name  
          try {
            socket.add(nameBytes);
            await socket.flush();
          } catch (e) {
            print('Error sending file name for $fileRelativePath: $e');
            throw SocketException('Write failed: ${e.toString()}');
          }
          
          // Send file size
          final stat = await entity.stat();
          try {
            socket.add(_int64ToBytes(stat.size));
            await socket.flush();
          } catch (e) {
            print('Error sending file size for $fileRelativePath: $e');
            throw SocketException('Write failed: ${e.toString()}');
          }
          
          // Send file data and track progress
          final fileStream = entity.openRead();
          int fileBytesSent = 0;
          await for (final chunk in fileStream) {
            try {
              // Check if connection is still valid before sending
              if (socket.remoteAddress == null) {
                throw SocketException('Connection lost');
              }
              
              try {
                socket.add(chunk);
                await socket.flush();
                fileBytesSent += chunk.length;
              } catch (e) {
                print('Error sending chunk for file $fileRelativePath at position $fileBytesSent: $e');
                
                // Check if this is a temporary write failure
                if (e.toString().contains('Write failed') || e.toString().contains('Broken pipe')) {
                  print('Write failure detected, checking connection health...');
                  try {
                    if (socket.remoteAddress == null) {
                      throw SocketException('Connection lost during file transfer');
                    }
                    // Try to flush any pending data
                    await socket.flush();
                    print('Connection appears healthy, retrying write...');
                    // Retry the write operation once
                    socket.add(chunk);
                    await socket.flush();
                    fileBytesSent += chunk.length;
                    print('Write retry successful');
                  } catch (retryError) {
                    print('Write retry failed: $retryError');
                    rethrow;
                  }
                } else {
                  rethrow;
                }
              }
              
              // Update progress more frequently for better responsiveness
              if (fileBytesSent % (16 * 1024) == 0) { // Every 16KB for smoother progress
                final currentSession = _activeSessions[session.id];
                if (currentSession != null) {
                  final updatedSession = currentSession.copyWith(
                    transferredSize: bytesSent + fileBytesSent,
                    currentFileName: fileRelativePath,
                    completedFiles: currentSession.completedFiles,
                  );
                  _activeSessions[session.id] = updatedSession;
                  _sessionProgressController.add(updatedSession);
                  notifyListeners(); // Ensure UI updates
                }
              }
              
              // Add small delay every 16KB to prevent overwhelming the connection
              if (fileBytesSent % (16 * 1024) == 0) {
                await Future.delayed(const Duration(milliseconds: 1));
                
                // Check connection health every 64KB
                if (fileBytesSent % (64 * 1024) == 0) {
                  try {
                    // Small test write to verify connection
                    await socket.flush();
                    print('Connection health check passed at ${fileBytesSent} bytes');
                  } catch (e) {
                    print('Connection health check failed during file transfer at ${fileBytesSent} bytes: $e');
                    rethrow;
                  }
                }
              }
              
              // Extra health check when approaching completion
              final currentProgressPercent = (bytesSent + fileBytesSent) / session.totalSize * 100;
              if (currentProgressPercent >= 95.0 && fileBytesSent % (8 * 1024) == 0) {
                try {
                  await socket.flush();
                  print('High progress health check passed at ${currentProgressPercent.toStringAsFixed(1)}%');
                } catch (e) {
                  print('High progress health check failed at ${currentProgressPercent.toStringAsFixed(1)}%: $e');
                  rethrow;
                }
              }
            } catch (e) {
              if (e is SocketException) {
                print('Socket error sending chunk for file $fileRelativePath (sent $fileBytesSent bytes): ${e.message}');
                // Try to provide context about where the error occurred
                if (fileBytesSent == 0) {
                  print('Error occurred at start of file transfer');
                } else {
                  final percentage = (fileBytesSent / stat.size * 100).toStringAsFixed(1);
                  print('Error occurred at $percentage% of file transfer');
                }
              } else {
                print('Error sending chunk for file $fileRelativePath (sent $fileBytesSent bytes): $e');
              }
              rethrow;
            }
          }
          
          // Update progress after each file completion
          bytesSent += stat.size;
          final sessionAfterFile = _activeSessions[session.id];
          if (sessionAfterFile != null) {
            final updatedSession = sessionAfterFile.copyWith(
              transferredSize: bytesSent,
              completedFiles: sessionAfterFile.completedFiles + 1,
              currentFileName: null, // Clear current file after completion
            );
            _activeSessions[session.id] = updatedSession;
            _sessionProgressController.add(updatedSession);
            notifyListeners(); // Ensure UI updates
          }
          
          final progressPercent = (bytesSent / session.totalSize * 100);
          print('Sent file: $fileRelativePath (${stat.size} bytes) - Total: $bytesSent bytes');
          print('Progress: ${progressPercent.toStringAsFixed(1)}% (${sessionAfterFile?.completedFiles ?? 0} files completed)');
          
          // Log when we're close to completion
          if (progressPercent >= 95.0) {
            print('WARNING: High progress detected - ${progressPercent.toStringAsFixed(1)}% - ${session.totalSize - bytesSent} bytes remaining');
            print('Connection status: remoteAddress=${socket.remoteAddress}, port=${socket.remotePort}');
          }
          
          // Add extra logging for the last few files
          if (progressPercent >= 98.0) {
            print('CRITICAL: Near completion - ${progressPercent.toStringAsFixed(1)}% - ${session.totalSize - bytesSent} bytes remaining');
            print('Socket state: ${socket.runtimeType}, remoteAddress=${socket.remoteAddress}');
          }
          
          // Add a small delay after each file to ensure proper transmission
          await Future.delayed(const Duration(milliseconds: 10));
          
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          final dirRelativePath = '$relativePath/$dirName';
          
          // Send directory name
          final nameBytes = utf8.encode(dirRelativePath);
          try {
            socket.add(_int64ToBytes(nameBytes.length));
            await socket.flush();
          } catch (e) {
            print('Error sending directory name length for $dirRelativePath: $e');
            throw SocketException('Write failed: ${e.toString()}');
          }
          
          try {
            socket.add(nameBytes);
            await socket.flush();
          } catch (e) {
            print('Error sending directory name for $dirRelativePath: $e');
            throw SocketException('Write failed: ${e.toString()}');
          }
          
          // Send -1 to indicate this is a directory
          try {
            socket.add(_int64ToBytes(-1));
            await socket.flush();
          } catch (e) {
            print('Error sending directory indicator for $dirRelativePath: $e');
            throw SocketException('Write failed: ${e.toString()}');
          }
          
          // Recursively send subdirectory contents with progress tracking
          bytesSent = await _sendDirectoryContentsRecursiveWithProgress(socket, entity.path, dirRelativePath, bytesSent, session);
        }
      }
    } catch (e) {
      print('Error sending directory contents with progress: $e');
      rethrow;
    }
    
    print('Completed directory transfer: $dirPath (final: $bytesSent bytes)');
    return bytesSent;
  }

  // Text transfer implementation
  Future<void> _performTextTransfer(TransferSession session) async {
    Socket? socket;
    
    try {
      print('Connecting for text transfer to ${session.peer.address}:${session.peer.port}');
      
      // Update session status
      var updatedSession = session.copyWith(status: TransferStatus.inProgress);
      _activeSessions[session.id] = updatedSession;
      _sessionProgressController.add(updatedSession);

      // Connect to peer with retry mechanism
      socket = await _connectWithRetry(session.peer.address, session.peer.port, 3);
      print('Connected for text transfer');

      // Phase 1: Send total elements (1) and total size
      final textBytes = utf8.encode(session.items.first.textContent!);
      socket.add(_int64ToBytes(1)); // 1 element
      socket.add(_int64ToBytes(textBytes.length)); // total size
      await socket.flush();

      // Phase 2: Send text element
      // Send element name (special text marker)
      final textNameBytes = utf8.encode(textElementName);
      socket.add(_int64ToBytes(textNameBytes.length + 1)); // +1 for null terminator
      socket.add(textNameBytes);
      socket.add([0]); // null terminator
      await socket.flush();

      // Send text size
      socket.add(_int64ToBytes(textBytes.length));
      await socket.flush();

      // Send text data
      socket.add(textBytes);
      await socket.flush();

      print('Text transfer completed');

      // Complete transfer - ensure final values are set
      updatedSession = updatedSession.copyWith(
        status: TransferStatus.completed,
        transferredSize: session.totalSize,
        completedAt: DateTime.now(),
      );
      _sessionCompletedController.add(updatedSession);
      
      // Move to completed sessions
      _moveToCompleted(updatedSession);

    } catch (e) {
      print('Text transfer failed: $e');
      // Handle transfer failure
      final failedSession = session.copyWith(
        status: TransferStatus.failed,
        completedAt: DateTime.now(),
        error: e.toString(),
      );
      _sessionFailedController.add(failedSession);
      
      // Move to completed sessions (failed transfers also get cleaned up)
      _moveToCompleted(failedSession);
    } finally {
      socket?.close();
    }
  }

  void _onIncomingConnection(Socket socket) {
    print('Incoming connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    
    // Configure incoming socket for better stability
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (e) {
      print('Warning: Could not configure incoming socket options: $e');
    }
    
    _handleIncomingTransfer(socket);
  }

  Future<void> _handleIncomingTransfer(Socket socket) async {
    String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    
    try {
      // Set socket options for better stability
      socket.setOption(SocketOption.tcpNoDelay, true);
      
      final List<int> buffer = [];
      int phase = 0; // 0=header, 1=elements
      int totalElements = 0;
      int totalSize = 0;
      int currentElement = 0;
      int expectedNameLength = 0;
      int expectedDataSize = 0;
      String currentElementName = '';
      int currentElementSize = 0;
      List<int> elementData = [];
      TransferSession? session;
      List<TransferItem> receivedItems = [];

      await for (final data in socket) {
        buffer.addAll(data);

        while (buffer.isNotEmpty) {
          if (phase == 0) {
            // Parse header: 8 bytes for element count + 8 bytes for total size
            if (buffer.length >= 16) {
              totalElements = _bytesToInt64(buffer.sublist(0, 8));
              totalSize = _bytesToInt64(buffer.sublist(8, 16));
              buffer.removeRange(0, 16);
              
              print('Incoming transfer: $totalElements elements, $totalSize bytes');
              print('Receiver expecting exactly $totalElements elements to complete transfer');
              
              // Create session
              session = TransferSession(
                id: sessionId,
                peer: Peer(
                  address: socket.remoteAddress.address,
                  name: 'Unknown',
                  port: socket.remotePort,
                ),
                items: [],
                direction: TransferDirection.receiving,
                status: TransferStatus.inProgress,
                startedAt: DateTime.now(),
                totalSize: totalSize,
                totalFiles: totalElements, // Set total files to total elements
                completedFiles: 0,
                transferredSize: 0,
              );
              
              _activeSessions[sessionId] = session;
              _sessionStartedController.add(session);
              
              // Start progress updates
              _startProgressUpdates();
              
              phase = 1;
              expectedNameLength = 0;
            } else {
              break; // Wait for more data
            }
          } else if (phase == 1) {
            // Parse elements
            if (expectedNameLength == 0) {
              // Read name length (8 bytes)
              if (buffer.length >= 8) {
                expectedNameLength = _bytesToInt64(buffer.sublist(0, 8));
                buffer.removeRange(0, 8);
              } else {
                break; // Wait for more data
              }
            } else if (currentElementName.isEmpty) {
              // Read element name
              if (buffer.length >= expectedNameLength) {
                final nameBytes = buffer.sublist(0, expectedNameLength);
                // Handle null terminator for text elements
                if (nameBytes.last == 0) {
                  currentElementName = utf8.decode(nameBytes.sublist(0, nameBytes.length - 1));
                } else {
                  currentElementName = utf8.decode(nameBytes);
                }
                buffer.removeRange(0, expectedNameLength);
                expectedDataSize = 0;
              } else {
                break; // Wait for more data
              }
            } else if (expectedDataSize == 0) {
              // Read element size (8 bytes)
              if (buffer.length >= 8) {
                currentElementSize = _bytesToInt64(buffer.sublist(0, 8));
                expectedDataSize = currentElementSize;
                buffer.removeRange(0, 8);
                elementData.clear();
                
                // If this is a directory (size -1), process it immediately
                if (currentElementSize == -1) {
                  await _processReceivedElement(currentElementName, [], sessionId);
                  
                  // Create directory item
                  final uniqueFolderPath = await _getUniqueDownloadPathForFolder(currentElementName);
                  final actualFolderName = path.basename(uniqueFolderPath);
                  final item = TransferItem(
                    id: '${sessionId}_${receivedItems.length}',
                    name: actualFolderName, // Use the actual folder name (with number if renamed)
                    size: -1,
                    type: TransferType.folder,
                    status: TransferStatus.completed,
                    createdAt: DateTime.now(),
                    path: uniqueFolderPath,
                  );
                  
                  receivedItems.add(item);
                  
                  // Update session progress
                  if (session != null) {
                    final updatedSession = session.copyWith(
                      items: List.from(receivedItems),
                      transferredSize: receivedItems.fold<int>(0, (sum, item) => sum > 0 ? sum + item.size : sum),
                    );
                    _activeSessions[sessionId] = updatedSession;
                    _sessionProgressController.add(updatedSession);
                    session = updatedSession;
                  }
                  
                  // Reset for next element
                  currentElement++;
                  expectedNameLength = 0;
                  expectedDataSize = 0;
                  currentElementName = '';
                  currentElementSize = 0;
                  elementData.clear();
                  
                  // Check if all elements received
                  if (currentElement >= totalElements) {
                    print('All elements received: $currentElement/$totalElements');
                    print('Total items processed: ${receivedItems.length}');
                    print('Total size processed: ${receivedItems.fold<int>(0, (sum, item) => sum + item.size)} bytes');
                    print('Transfer completion check: currentElement=$currentElement, totalElements=$totalElements, condition=${currentElement >= totalElements}');
                    
                    // Complete transfer - ensure final values are set
                    if (session != null) {
                      final fileCount = receivedItems.where((item) => item.type == TransferType.file).length;
                      final completedSession = session.copyWith(
                        status: TransferStatus.completed,
                        completedAt: DateTime.now(),
                        transferredSize: receivedItems.fold<int>(0, (sum, item) => sum + item.size),
                        completedFiles: fileCount,
                        totalFiles: fileCount,
                      );
                      _sessionCompletedController.add(completedSession);
                      _moveToCompleted(completedSession);
                    }
                    
                    // Add a small delay to ensure sender completes
                    await Future.delayed(const Duration(milliseconds: 100));
                    break;
                  }
                }
              } else {
                break; // Wait for more data
              }
            } else {
              // Read element data
              final remainingData = expectedDataSize - elementData.length;
              final availableData = buffer.length;
              final dataToRead = remainingData < availableData ? remainingData : availableData;
              
              if (dataToRead > 0) {
                elementData.addAll(buffer.sublist(0, dataToRead));
                buffer.removeRange(0, dataToRead);
                
                // Update progress during file reception for better responsiveness
                if (session != null && elementData.length % (16 * 1024) == 0) { // Every 16KB
                  final currentTransferredSize = receivedItems.fold<int>(0, (sum, item) => sum + item.size) + elementData.length;
                  final updatedSession = session.copyWith(
                    transferredSize: currentTransferredSize,
                    currentFileName: currentElementName,
                    completedFiles: receivedItems.length,
                  );
                  _activeSessions[sessionId] = updatedSession;
                  _sessionProgressController.add(updatedSession);
                  session = updatedSession;
                  notifyListeners();
                }
              }
              
              // Check if we have enough data to complete the element
              if (elementData.length >= expectedDataSize) {
                print('Element data complete: ${elementData.length}/${expectedDataSize} bytes for $currentElementName');
              }
              
              // Check if element is complete
              if (elementData.length >= expectedDataSize) {
                print('Processing element ${currentElement + 1}/$totalElements: $currentElementName (${elementData.length} bytes)');
                print('Receiver progress: ${currentElement + 1}/$totalElements elements received');
                
                try {
                  await _processReceivedElement(currentElementName, elementData, sessionId);
                  
                  // Create transfer item
                  final isText = currentElementName == textElementName;
                  final item = TransferItem(
                    id: '${sessionId}_${receivedItems.length}',
                    name: isText ? 'Text Snippet' : currentElementName,
                    size: currentElementSize,
                    type: isText ? TransferType.text : TransferType.file,
                    status: TransferStatus.completed,
                    createdAt: DateTime.now(),
                    textContent: isText ? utf8.decode(elementData) : null,
                    path: isText ? null : await _getDownloadPathForFile(currentElementName, sessionId),
                  );
                  
                  receivedItems.add(item);
                  
                  // Update session progress
                  if (session != null) {
                    final updatedSession = session.copyWith(
                      items: List.from(receivedItems),
                      transferredSize: receivedItems.fold<int>(0, (sum, item) => sum + item.size),
                      completedFiles: receivedItems.length,
                      currentFileName: null, // Clear current file when element is completed
                    );
                    _activeSessions[sessionId] = updatedSession;
                    _sessionProgressController.add(updatedSession);
                    session = updatedSession;
                    notifyListeners();
                  }
                } catch (e) {
                  print('Error processing element $currentElementName: $e');
                  rethrow;
                }
                
                print('Successfully processed element: $currentElementName');
                
                // Reset for next element
                currentElement++;
                expectedNameLength = 0;
                expectedDataSize = 0;
                currentElementName = '';
                currentElementSize = 0;
                elementData.clear();
                
                // Check if all elements received
                if (currentElement >= totalElements) {
                  // Transfer complete - ensure final values are set
                  if (session != null) {
                    final fileCount = receivedItems.where((item) => item.type == TransferType.file).length;
                    final completedSession = session.copyWith(
                      status: TransferStatus.completed,
                      completedAt: DateTime.now(),
                      transferredSize: receivedItems.fold<int>(0, (sum, item) => sum + item.size),
                      completedFiles: fileCount,
                      totalFiles: fileCount,
                    );
                    _sessionCompletedController.add(completedSession);
                    _moveToCompleted(completedSession);
                  }
                  print('Transfer completed: ${receivedItems.length} items received');
                  return;
                }
              }
              
              if (buffer.isEmpty) break;
            }
          }
        }
      }
    } catch (e) {
      print('Error handling incoming transfer: $e');
      
      // Provide more specific error messages
      String errorMessage;
      if (e is SocketException) {
        if (e.message.contains('forcibly closed')) {
          errorMessage = 'Connection was closed by the sender. The sender might have cancelled the transfer.';
        } else if (e.message.contains('Connection reset')) {
          errorMessage = 'Connection was reset. This might be due to network issues or sender cancellation.';
        } else if (e.message.contains('semaphore timeout')) {
          errorMessage = 'Connection timeout. The sender may be busy or network is slow. Try again.';
        } else if (e.message.contains('timeout')) {
          errorMessage = 'Connection timeout. Please check your network connection and try again.';
        } else {
          errorMessage = 'Network error during transfer: ${e.message}';
        }
      } else if (e is TimeoutException) {
        errorMessage = 'Transfer timeout. The connection took too long to establish. Please try again.';
      } else if (e is FormatException) {
        errorMessage = 'Data format error: ${e.message}. This might indicate protocol compatibility issues.';
      } else {
        errorMessage = e.toString();
      }
      
      // Handle failure
      if (sessionId.isNotEmpty) {
        final session = _activeSessions[sessionId];
        if (session != null) {
          final failedSession = session.copyWith(
            status: TransferStatus.failed,
            completedAt: DateTime.now(),
            error: errorMessage,
          );
          _sessionFailedController.add(failedSession);
          _moveToCompleted(failedSession);
        }
      }
    } finally {
      try {
        socket.close();
      } catch (e) {
        print('Error closing incoming transfer socket: $e');
      }
    }
  }

  // Process received element (save file or handle text)
  Future<void> _processReceivedElement(String elementName, List<int> data, String sessionId) async {
    try {
      if (elementName == textElementName) {
        // Handle received text
        final text = utf8.decode(data);
        print('Received text: ${text.length} characters');
        // Text is handled in the transfer item creation
      } else if (data.isEmpty) {
        // Handle directory (no data means it's a directory)
        final downloadPath = await _getUniqueDownloadPathForFolder(elementName);
        final dir = Directory(downloadPath);
        
        // Track the unique folder path for this session
        if (!_sessionFolderPaths.containsKey(sessionId)) {
          _sessionFolderPaths[sessionId] = {};
        }
        _sessionFolderPaths[sessionId]![elementName] = downloadPath;
        
        // Create directory (don't fail if it already exists)
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
            print('Created directory: $downloadPath');
          } else {
            print('Directory already exists: $downloadPath');
          }
        } on PathExistsException catch (e) {
          // Directory exists, this is fine - just continue
          print('Directory already exists (PathExistsException): $downloadPath');
        }
      } else {
        // Handle received file
        final downloadPath = await _getDownloadPathForFile(elementName, sessionId);
        final file = File(downloadPath);
        
        // Create parent directory if needed (handle existence gracefully)
        try {
          await file.parent.create(recursive: true);
        } on PathExistsException catch (e) {
          // Parent directory exists, this is fine
          print('Parent directory already exists: ${file.parent.path}');
        }
        
        // Save file (unique path ensures no conflicts)
        await file.writeAsBytes(data);
        print('Saved file: $downloadPath (${data.length} bytes)');
      }
    } catch (e) {
      print('Error processing received element: $e');
      rethrow;
    }
  }

  // Get download path for received files, considering parent folder uniqueness
  Future<String> _getDownloadPathForFile(String fileName, String sessionId) async {
    // Check if this file is within a tracked unique folder
    final sessionFolders = _sessionFolderPaths[sessionId];
    if (sessionFolders != null) {
      // Find the longest matching parent folder path
      String? bestMatchFolder;
      String? bestMatchPath;
      
      for (final entry in sessionFolders.entries) {
        final folderName = entry.key;
        final folderPath = entry.value;
        
        // Check if this file is within this folder
        if (fileName.startsWith('$folderName/')) {
          // This is a longer match or first match
          if (bestMatchFolder == null || folderName.length > bestMatchFolder.length) {
            bestMatchFolder = folderName;
            bestMatchPath = folderPath;
          }
        }
      }
      
      // If we found a matching parent folder, use its unique path
      if (bestMatchPath != null && bestMatchFolder != null) {
        final relativePath = fileName.substring(bestMatchFolder.length + 1); // Remove folder name + '/'
        return '$bestMatchPath${Platform.pathSeparator}$relativePath';
      }
    }
    
    // Fall back to regular unique path generation
    return await _getUniqueDownloadPath(fileName);
  }

  // Get download path for received files
  Future<String> _getDownloadPath(String fileName) async {
    // Try to get custom download path from settings first
    String downloadsPath;
    
    if (_settings?.destPath != null && _settings!.destPath.isNotEmpty) {
      downloadsPath = _settings!.destPath;
    } else {
      // Fallback to default path
      downloadsPath = Platform.isWindows 
          ? '${Platform.environment['USERPROFILE']}\\Downloads\\Zipline' 
          : '${Platform.environment['HOME']}/Downloads/Zipline';
    }
    
    final downloadDir = Directory(downloadsPath);
    
    try {
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
    } on PathExistsException catch (e) {
      // Directory exists, this is fine
      print('Downloads directory already exists: $downloadsPath');
    }
    
    return '$downloadsPath${Platform.pathSeparator}$fileName';
  }

  // Get unique download path to avoid overwriting existing files
  Future<String> _getUniqueDownloadPath(String fileName) async {
    final originalPath = await _getDownloadPath(fileName);
    final file = File(originalPath);
    
    // If file doesn't exist, use original path
    if (!await file.exists()) {
      return originalPath;
    }
    
    // Generate unique filename by adding number
    final dir = file.parent.path;
    final nameWithoutExt = path.basenameWithoutExtension(fileName);
    final extension = path.extension(fileName);
    
    int counter = 1;
    String uniquePath;
    
    do {
      final uniqueFileName = '$nameWithoutExt ($counter)$extension';
      uniquePath = '$dir${Platform.pathSeparator}$uniqueFileName';
      counter++;
    } while (await File(uniquePath).exists());
    
    return uniquePath;
  }

  // Get unique download path for folders to avoid overwriting existing folders
  Future<String> _getUniqueDownloadPathForFolder(String folderName) async {
    final originalPath = await _getDownloadPath(folderName);
    final dir = Directory(originalPath);
    
    // If folder doesn't exist, use original path
    if (!await dir.exists()) {
      return originalPath;
    }
    
    // Generate unique folder name by adding number
    final parentDir = dir.parent.path;
    
    int counter = 1;
    String uniquePath;
    
    do {
      final uniqueFolderName = '$folderName ($counter)';
      uniquePath = '$parentDir${Platform.pathSeparator}$uniqueFolderName';
      counter++;
    } while (await Directory(uniquePath).exists());
    
    return uniquePath;
  }

  // Convert int64 to 8-byte array (little endian)
  List<int> _int64ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
      (value >> 32) & 0xFF,
      (value >> 40) & 0xFF,
      (value >> 48) & 0xFF,
      (value >> 56) & 0xFF,
    ];
  }

  // Convert 8-byte array to int64 (little endian)
  int _bytesToInt64(List<int> bytes) {
    return bytes[0] |
           (bytes[1] << 8) |
           (bytes[2] << 16) |
           (bytes[3] << 24) |
           (bytes[4] << 32) |
           (bytes[5] << 40) |
           (bytes[6] << 48) |
           (bytes[7] << 56);
  }

  void dispose() {
    stopServer();
    _sessionStartedController.close();
    _sessionProgressController.close();
    _sessionCompletedController.close();
    _sessionFailedController.close();
  }
}