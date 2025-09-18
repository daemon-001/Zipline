import 'package:flutter/material.dart';
import '../models/transfer_session.dart';
import '../models/transfer_item.dart';

class TransferProgressDialog extends StatefulWidget {
  final TransferSession session;
  final VoidCallback? onCancel;

  const TransferProgressDialog({
    Key? key,
    required this.session,
    this.onCancel,
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
        widget.session.startedAt != null) {
      final elapsed = DateTime.now().difference(widget.session.startedAt!);
      if (elapsed.inSeconds > 0) {
        final bytesPerSecond = widget.session.transferredSize / elapsed.inSeconds;
        return _formatBytes(bytesPerSecond.round()) + '/s';
      }
    }
    return '';
  }

  String _getEstimatedTimeText() {
    if (widget.session.status == TransferStatus.inProgress && 
        widget.session.startedAt != null &&
        widget.session.transferredSize > 0) {
      final elapsed = DateTime.now().difference(widget.session.startedAt!);
      final bytesPerSecond = widget.session.transferredSize / elapsed.inSeconds;
      if (bytesPerSecond > 0) {
        final remainingBytes = widget.session.totalSize - widget.session.transferredSize;
        final remainingSeconds = (remainingBytes / bytesPerSecond).round();
        if (remainingSeconds > 0) {
          return _formatDuration(Duration(seconds: remainingSeconds));
        }
      }
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

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  Color _getStatusColor() {
    switch (widget.session.status) {
      case TransferStatus.pending:
        return Colors.orange;
      case TransferStatus.inProgress:
        return Colors.blue;
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
        return Colors.red;
      case TransferStatus.cancelled:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (widget.session.status) {
      case TransferStatus.pending:
        return 'Preparing...';
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
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getTransferTitle(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (widget.onCancel != null && 
                        widget.session.status == TransferStatus.inProgress)
                      IconButton(
                        onPressed: () {
                          widget.onCancel?.call();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.close),
                        color: Colors.grey[600],
                        iconSize: 20,
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
                        color: Colors.grey[200],
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
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
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_getTransferSpeedText().isNotEmpty)
                          Text(
                            _getTransferSpeedText(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    
                    if (_getEstimatedTimeText().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Files: ${widget.session.completedFiles}/${widget.session.totalFiles}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            'ETA: ${_getEstimatedTimeText()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
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
      ),
    );
  }
}