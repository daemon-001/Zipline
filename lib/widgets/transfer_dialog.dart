import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/transfer_session.dart';
import '../services/file_transfer_service.dart';
import 'package:provider/provider.dart';

class TransferDialog extends StatefulWidget {
  final Peer peer;
  final VoidCallback? onClose;

  const TransferDialog({
    super.key,
    required this.peer,
    this.onClose,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog>
    with TickerProviderStateMixin {
  bool _isDragOver = false;
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
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
        child: Container(
          width: 400,
          constraints: const BoxConstraints(maxHeight: 380),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                _buildHeader(context, theme),
                
                // Content
                Expanded(
                  child: _buildContent(context, theme, isDark),
                ),
                
                // Buttons
                _buildButtons(context, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Text(
            'File transfer',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
              fontFamily: 'Klill',
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClose?.call();
            },
            icon: Icon(
              Icons.close,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DragTarget<List<String>>(
        onWillAccept: (data) {
          setState(() {
            _isDragOver = true;
          });
          return true;
        },
        onAccept: (data) {
          setState(() {
            _isDragOver = false;
          });
          _sendFiles(data);
        },
        onLeave: (data) {
          setState(() {
            _isDragOver = false;
          });
        },
        builder: (context, candidateData, rejectedData) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _isDragOver 
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isDragOver 
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
                width: _isDragOver ? 2 : 1,
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
                    width: _isDragOver ? 60 : 48,
                    height: _isDragOver ? 60 : 48,
                    decoration: BoxDecoration(
                      color: _isDragOver 
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _isDragOver ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ] : null,
                    ),
                    child: Icon(
                      _isDragOver ? Icons.cloud_upload : Icons.cloud_upload_outlined,
                      size: _isDragOver ? 30 : 24,
                      color: _isDragOver 
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Drag and drop text
                  Text(
                    _isDragOver 
                        ? 'Drop files here to send'
                        : 'Drag and drop files here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isDragOver 
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                      fontFamily: 'LiberationSans',
                      fontWeight: _isDragOver ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  
                  if (_isDragOver) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Release to send',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontFamily: 'LiberationSans',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildButtons(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(
                    fontSize: 12,
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
          
          const SizedBox(height: 16),
          
          // Buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.file_present_outlined, size: 20),
                  label: const Text(
                    'Send File',
                    style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_outlined, size: 20),
                  label: const Text(
                    'Send Folder',
                    style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: theme.colorScheme.onSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        final filePaths = result.paths
            .where((path) => path != null)
            .cast<String>()
            .toList();

        if (filePaths.isNotEmpty) {
          await _sendFiles(filePaths);
        }
      }
    } catch (e) {
      _showError('Failed to pick files: $e');
    }
  }

  Future<void> _pickFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        await _sendFiles([selectedDirectory]);
      }
    } catch (e) {
      _showError('Failed to pick folder: $e');
    }
  }

  Future<void> _sendFiles(List<String> filePaths) async {
    final fileTransfer = Provider.of<FileTransferService>(context, listen: false);
    
    try {
      // Convert file paths to TransferItems
      final List<TransferItem> items = [];
      
      for (final path in filePaths) {
        final stat = await FileStat.stat(path);
        final name = path.split('\\').last;
        
        if (stat.type == FileSystemEntityType.directory) {
          items.add(TransferItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: TransferType.folder,
            name: name,
            path: path,
            createdAt: DateTime.now(),
            size: -1,
            status: TransferStatus.pending,
          ));
        } else {
          items.add(TransferItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: TransferType.file,
            name: name,
            path: path,
            createdAt: DateTime.now(),
            size: stat.size,
            status: TransferStatus.pending,
          ));
        }
      }
      
      final success = await fileTransfer.sendFiles(widget.peer, items);
      
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          final theme = Theme.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'File transfer started',
                style: TextStyle(fontFamily: 'LiberationSans'),
              ),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'LiberationSans'),
        ),
        backgroundColor: theme.colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
