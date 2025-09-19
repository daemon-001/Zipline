import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as path;
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/transfer_session.dart';
import '../services/file_transfer_service.dart';
import '../services/profile_image_service.dart';
import '../widgets/buddy_list_item.dart';
import '../widgets/transfer_progress_widget.dart';
import '../widgets/top_notification.dart';

class TransferPage extends StatefulWidget {
  final Peer peer;
  final VoidCallback? onBack;

  const TransferPage({
    super.key,
    required this.peer,
    this.onBack,
  });

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage>
    with TickerProviderStateMixin {
  bool _isDragOver = false;
  bool _isDisposed = false;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    _fadeController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _isDisposed = true;
    
    // Stop animations before disposing to prevent platform channel errors
    if (_fadeController.isAnimating) {
      _fadeController.stop();
    }
    if (_scaleController.isAnimating) {
      _scaleController.stop();
    }
    
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Column(
            children: [
              // Header with back button and title
              _buildHeader(context, theme),
              
              // Buddy details section
              _buildBuddyDetails(context, theme),
              
              // Main transfer content
              Expanded(
                child: _buildTransferContent(context, theme, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // Dispose animation controllers before navigation to prevent plugin errors
              _fadeController.stop();
              _scaleController.stop();
              
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: Icon(
              Icons.arrow_back_ios,
              color: theme.colorScheme.onSurface,
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'File Transfer',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
              fontFamily: 'Klill',
            ),
          ),
          const Spacer(),
          // Connection status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'LiberationSans',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuddyDetails(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: BuddyListItem(
        peer: widget.peer,
        isLocalPeer: false,
        onTap: null, // No tap action needed in transfer page
      ),
    );
  }

  Widget _buildTransferContent(BuildContext context, ThemeData theme, bool isDark) {
    return Consumer<FileTransferService>(
      builder: (context, fileTransfer, child) {
        // Get active sessions for this peer
        final activeSessions = fileTransfer.activeSessions.values
            .where((session) => session.peer.address == widget.peer.address)
            .toList();
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              // Active transfers section
              if (activeSessions.isNotEmpty) ...[
                Expanded(
                  flex: 1,
                  child: ListView.builder(
                    itemCount: activeSessions.length,
                    itemBuilder: (context, index) {
                      final session = activeSessions[index];
                      return TransferProgressWidget(
                        session: session,
                        onCancel: () {
                          fileTransfer.cancelTransfer(session.id);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
              
              // Drag and drop area
              Expanded(
                flex: activeSessions.isNotEmpty ? 2 : 3,
                child: DropTarget(
                  onDragEntered: (details) {
                    setState(() {
                      _isDragOver = true;
                    });
                  },
                  onDragExited: (details) {
                    setState(() {
                      _isDragOver = false;
                    });
                  },
                  onDragDone: (details) {
                    setState(() {
                      _isDragOver = false;
                    });
                    // Extract file paths from dropped files
                    final filePaths = details.files.map((file) => file.path).toList();
                    if (filePaths.isNotEmpty) {
                      _sendFiles(filePaths);
                    }
                  },
                  child: _buildDragDropArea(context, theme, isDark),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Action buttons
              _buildActionButtons(context, theme),
              
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragDropArea(BuildContext context, ThemeData theme, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _isDragOver 
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isDragOver 
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.2),
          width: _isDragOver ? 3 : 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Cloud upload icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isDragOver ? 80 : 64,
              height: _isDragOver ? 80 : 64,
              decoration: BoxDecoration(
                color: _isDragOver 
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _isDragOver ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ] : [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                _isDragOver ? Icons.cloud_upload : Icons.cloud_upload_outlined,
                size: _isDragOver ? 40 : 32,
                color: _isDragOver 
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Drag and drop text
            Text(
              _isDragOver 
                  ? 'Drop files here to send'
                  : 'Drag and drop files here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: _isDragOver 
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontFamily: 'LiberationSans',
                fontWeight: _isDragOver ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'or use the buttons below',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontFamily: 'LiberationSans',
              ),
            ),
            
            if (_isDragOver) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Release to send',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                    fontFamily: 'LiberationSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        // Divider with "or"
        Row(
          children: [
            Expanded(
              child: Divider(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                thickness: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'or',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontFamily: 'LiberationSans',
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                thickness: 1,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // Action buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.file_present_outlined, size: 24),
                label: const Text(
                  'Send Files',
                  style: TextStyle(
                    fontFamily: 'Klill', 
                    fontWeight: FontWeight.w600, 
                    fontSize: 16,
                  ),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_outlined, size: 24),
                label: const Text(
                  'Send Folder',
                  style: TextStyle(
                    fontFamily: 'Klill', 
                    fontWeight: FontWeight.w600, 
                    fontSize: 16,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: theme.colorScheme.onSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickFiles() async {
    if (_isDisposed) return;
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (_isDisposed) return;

      if (result != null && result.files.isNotEmpty) {
        final filePaths = result.paths
            .where((path) => path != null)
            .cast<String>()
            .toList();

        if (filePaths.isNotEmpty && !_isDisposed) {
          await _sendFiles(filePaths);
        }
      }
    } catch (e) {
      if (!_isDisposed) {
        _showError('Failed to pick files: $e');
      }
    }
  }

  Future<void> _pickFolder() async {
    if (_isDisposed) return;
    
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (_isDisposed) return;

      if (selectedDirectory != null) {
        await _sendFiles([selectedDirectory]);
      }
    } catch (e) {
      if (!_isDisposed) {
        _showError('Failed to pick folder: $e');
      }
    }
  }

  Future<void> _sendFiles(List<String> filePaths) async {
    if (_isDisposed) return;
    
    final fileTransfer = Provider.of<FileTransferService>(context, listen: false);
    
    try {
      // Convert file paths to TransferItems
      final List<TransferItem> items = [];
      
      for (final filePath in filePaths) {
        final stat = await FileStat.stat(filePath);
        final name = path.basename(filePath);
        
        if (stat.type == FileSystemEntityType.directory) {
          items.add(TransferItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: TransferType.folder,
            name: name,
            path: filePath,
            createdAt: DateTime.now(),
            size: -1,
            status: TransferStatus.pending,
          ));
        } else {
          items.add(TransferItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: TransferType.file,
            name: name,
            path: filePath,
            createdAt: DateTime.now(),
            size: stat.size,
            status: TransferStatus.pending,
          ));
        }
      }
      
      final success = await fileTransfer.sendFiles(widget.peer, items);
      
      if (success) {
        if (mounted) {
          TopNotification.show(
            context,
            title: 'Transfer Started',
            message: 'File transfer has been initiated',
            type: NotificationType.success,
          );
        }
      } else {
        _showError('Failed to start file transfer');
      }
    } catch (e) {
      _showError('Failed to send files: $e');
    }
  }

  void _showError(String message) {
    if (_isDisposed || !mounted) return;
    
    TopNotification.show(
      context,
      title: 'Error',
      message: message,
      type: NotificationType.error,
    );
  }
}
