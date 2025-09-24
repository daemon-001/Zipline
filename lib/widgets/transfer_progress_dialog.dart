import 'package:flutter/material.dart';
import '../models/transfer_session.dart';
import '../models/transfer_item.dart';

class TransferProgressDialog extends StatefulWidget {
  final TransferSession session;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;

  const TransferProgressDialog({
    Key? key,
    required this.session,
    this.onCancel,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<TransferProgressDialog> createState() => _TransferProgressDialogState();
}

class _TransferProgressDialogState extends State<TransferProgressDialog>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _fadeController;
  late Animation<double> _progressAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _fadeController.forward();
  }

  @override
  void didUpdateWidget(TransferProgressDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update progress animation when session changes
    if (widget.session != oldWidget.session) {
      final progress = _getOverallProgress();
      _progressController.animateTo(progress);
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  double _getOverallProgress() {
    if (widget.session.totalSize == 0) return 0.0;
    return (widget.session.transferredSize / widget.session.totalSize).clamp(0.0, 1.0);
  }

  String _getTransferSpeedText() {
    if (widget.session.status == TransferStatus.inProgress && 
        widget.session.currentSpeed > 0) {
      return _formatBytes(widget.session.currentSpeed.round()) + '/s';
    }
    return '';
  }


  String _formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  Color _getStatusColor() {
    final theme = Theme.of(context);
    switch (widget.session.status) {
      case TransferStatus.pending:
        return theme.colorScheme.tertiary;
      case TransferStatus.waitingForAcceptance:
        return theme.colorScheme.secondary;
      case TransferStatus.inProgress:
        return theme.colorScheme.primary;
      case TransferStatus.completed:
        return theme.colorScheme.primary;
      case TransferStatus.failed:
        return theme.colorScheme.error;
      case TransferStatus.cancelled:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _getStatusText() {
    switch (widget.session.status) {
      case TransferStatus.pending:
        return 'Preparing...';
      case TransferStatus.waitingForAcceptance:
        return 'Waiting for acceptance...';
      case TransferStatus.inProgress:
        return 'Transferring...';
      case TransferStatus.completed:
        return 'Completed';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _getTransferTitle() {
    if (widget.session.items.length == 1) {
      return widget.session.items.first.name;
    } else {
      final fileCount = widget.session.items.where((i) => i.type == TransferType.file).length;
      final folderCount = widget.session.items.where((i) => i.type == TransferType.folder).length;
      
      if (folderCount > 0 && fileCount > 0) {
        return '$fileCount files, $folderCount folders';
      } else if (folderCount > 0) {
        return folderCount == 1 ? '1 folder' : '$folderCount folders';
      } else {
        return fileCount == 1 ? '1 file' : '$fileCount files';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _getOverallProgress();
    final theme = Theme.of(context);
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.session.direction == TransferDirection.sending
                          ? Icons.upload
                          : Icons.download,
                      color: _getStatusColor(),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.session.direction == TransferDirection.sending
                                ? 'Sending to ${widget.session.peer.name}'
                                : 'Receiving from ${widget.session.peer.name}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getTransferTitle(),
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Progress content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Progress bar
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Progress info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _getStatusColor(),
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Size and speed info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_formatBytes(widget.session.transferredSize)} / ${_formatBytes(widget.session.totalSize)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_getTransferSpeedText().isNotEmpty)
                          Text(
                            _getTransferSpeedText(),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Action buttons
              _buildActionButtons(theme),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildActionButtons(ThemeData theme) {
    final status = widget.session.status;
    
    // Show different buttons based on status
    if (status == TransferStatus.completed || status == TransferStatus.failed || status == TransferStatus.cancelled) {
      // Show OK button for completed, failed, or cancelled transfers
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: () {
                widget.onDismiss?.call();
              },
              icon: Icon(
                status == TransferStatus.completed ? Icons.check : Icons.close,
                size: 16,
              ),
              label: const Text('OK'),
              style: FilledButton.styleFrom(
                backgroundColor: status == TransferStatus.completed 
                    ? theme.colorScheme.primary
                    : status == TransferStatus.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.outline,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    } else if ((status == TransferStatus.inProgress || status == TransferStatus.waitingForAcceptance) && widget.onCancel != null) {
      // Show Cancel/Abort button for in-progress and waiting transfers
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                widget.onCancel?.call();
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // No buttons for pending status
    return const SizedBox.shrink();
  }
}