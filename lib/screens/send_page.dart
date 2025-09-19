import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/transfer_session.dart';
import '../services/file_transfer_service.dart';
import '../widgets/top_notification.dart';

class SendPage extends StatefulWidget {
  final Peer peer;

  const SendPage({super.key, required this.peer});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  bool _isTextMode = false;
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
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _textController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Widget _buildPcProfileImage(BuildContext context) {
    final theme = Theme.of(context);
    
    // Use avatar URL from peer
    if (widget.peer.avatar != null && widget.peer.avatar!.isNotEmpty) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            widget.peer.avatar!,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to gradient if network image fails
              return _buildFallbackAvatar(context, theme);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              // Show loading indicator
              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    strokeWidth: 2,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      // Fallback to gradient with initial if no avatar URL
      return _buildFallbackAvatar(context, theme);
    }
  }

  Widget _buildFallbackAvatar(BuildContext context, ThemeData theme) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          widget.peer.name.isNotEmpty 
              ? widget.peer.name.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Klill',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Send to ${widget.peer.displayName}',
          style: const TextStyle(
            fontFamily: 'Klill',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Enhanced Peer info card
                  _buildEnhancedPeerCard(context, theme, isDark),
                  
                  const SizedBox(height: 24),
                  
                  // Enhanced Mode selector
                  _buildEnhancedModeSelector(context, theme, isDark),
                  
                  const SizedBox(height: 24),
                  
                  // Content area
                  Expanded(
                    child: _isTextMode ? _buildEnhancedTextMode(context, theme, isDark) : _buildEnhancedFileMode(context, theme, isDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedPeerCard(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            _buildPcProfileImage(context),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.displayName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                      fontFamily: 'Klill',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.peer.address}:${widget.peer.port}',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onPrimaryContainer,
                        fontFamily: 'LiberationSans',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.peer.platform != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _getPlatformIcon(widget.peer.platform!),
                          size: 16,
                          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.peer.platform!,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                            fontFamily: 'LiberationSans',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    if (platform.toLowerCase().contains('windows')) return Icons.desktop_windows;
    if (platform.toLowerCase().contains('mac')) return Icons.desktop_mac;
    if (platform.toLowerCase().contains('linux')) return Icons.desktop_windows;
    if (platform.toLowerCase().contains('android')) return Icons.android;
    if (platform.toLowerCase().contains('ios')) return Icons.phone_iphone;
    return Icons.computer;
  }

  Widget _buildEnhancedModeSelector(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(
            value: false,
            label: const Text(
              'Files',
              style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w500),
            ),
            icon: const Icon(Icons.folder_outlined),
          ),
          ButtonSegment<bool>(
            value: true,
            label: const Text(
              'Text',
              style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w500),
            ),
            icon: const Icon(Icons.text_fields_outlined),
          ),
        ],
        selected: {_isTextMode},
        onSelectionChanged: (Set<bool> newSelection) {
          setState(() {
            _isTextMode = newSelection.first;
          });
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return theme.colorScheme.primary;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return theme.colorScheme.onPrimary;
            }
            return theme.colorScheme.onSurface;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedTextMode(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Icon(
                  Icons.text_fields_outlined,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Enter text to send',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    fontFamily: 'Klill',
                  ),
                ),
              ],
            ),
          ),
          
          // Text input area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                    fontFamily: 'LiberationSans',
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type your message here...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontFamily: 'LiberationSans',
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(20),
                  ),
                ),
              ),
            ),
          ),
          
          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _sendText,
                    icon: const Icon(Icons.send),
                    label: const Text(
                      'Send Text',
                      style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.paste),
                  label: const Text(
                    'Paste',
                    style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: theme.colorScheme.onSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedFileMode(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Select files to send',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    fontFamily: 'Klill',
                  ),
                ),
              ],
            ),
          ),
          
          // Drag and drop area
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isDragOver 
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline.withValues(alpha: 0.3),
                        width: _isDragOver ? 3 : 2,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _isDragOver ? 100 : 80,
                            height: _isDragOver ? 100 : 80,
                            decoration: BoxDecoration(
                              color: _isDragOver 
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _isDragOver ? [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ] : null,
                            ),
                            child: Icon(
                              _isDragOver ? Icons.cloud_upload : Icons.cloud_upload_outlined,
                              size: _isDragOver ? 48 : 40,
                              color: _isDragOver 
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isDragOver 
                                ? 'Drop files here to send'
                                : 'Drag and drop files here',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: _isDragOver 
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              fontFamily: 'LiberationSans',
                              fontWeight: _isDragOver ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'or click the buttons below',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              fontFamily: 'LiberationSans',
                            ),
                          ),
                          if (_isDragOver) ...[
                            const SizedBox(height: 12),
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
            ),
          ),
          
          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.file_present_outlined),
                    label: const Text(
                      'Select Files',
                      style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text(
                      'Select Folder',
                      style: TextStyle(fontFamily: 'Klill', fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: theme.colorScheme.onSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
        // Use FileStat to safely handle files and directories
        final stat = await FileStat.stat(path);
        final name = path.split('\\').last;
        
        if (stat.type == FileSystemEntityType.directory) {
          // Directory item with size -1
          items.add(TransferItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: TransferType.folder,
            name: name,
            path: path,
            createdAt: DateTime.now(),
            size: -1, // Directories have size -1
            status: TransferStatus.pending,
          ));
        } else {
          // File item with actual size
          items.add(TransferItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: TransferType.file,
            name: name,
            path: path,
            createdAt: DateTime.now(),
            size: stat.size, // Use FileStat.size instead of File().lengthSync()
            status: TransferStatus.pending,
          ));
        }
      }
      
      final success = await fileTransfer.sendFiles(widget.peer, items);
      
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
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

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('Please enter some text to send');
      return;
    }

    final fileTransfer = Provider.of<FileTransferService>(context, listen: false);
    
    try {
      final success = await fileTransfer.sendText(widget.peer, text);
      
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          TopNotification.show(
            context,
            title: 'Text Sent',
            message: 'Text sent successfully',
            type: NotificationType.success,
          );
        }
      } else {
        _showError('Failed to send text');
      }
    } catch (e) {
      _showError('Failed to send text: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        setState(() {
          _textController.text = data.text!;
        });
      }
    } catch (e) {
      _showError('Failed to paste from clipboard: $e');
    }
  }

  void _showError(String message) {
    TopNotification.show(
      context,
      title: 'Error',
      message: message,
      type: NotificationType.error,
    );
  }
}