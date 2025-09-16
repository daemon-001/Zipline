import 'package:flutter/material.dart';
import '../models/transfer_session.dart';
import '../models/transfer_item.dart';

class TransferProgressWidget extends StatelessWidget {
  final TransferSession session;
  final VoidCallback? onCancel;

  const TransferProgressWidget({
    Key? key,
    required this.session,
    this.onCancel,
  }) : super(key: key);

  // Check if this is a folder transfer
  bool _isFolderTransfer() {
    return session.items.any((item) => item.type == TransferType.folder);
  }

  // Check if this is a single file transfer
  bool _isSingleFileTransfer() {
    return session.items.length == 1 && 
           session.items.any((item) => item.type == TransferType.file);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: session.status == TransferStatus.completed ? 2 : 4,
      color: session.status == TransferStatus.completed ? Colors.grey[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with direction and peer
            Row(
              children: [
                Icon(
                  session.direction == TransferDirection.sending
                      ? Icons.upload_outlined
                      : Icons.download_outlined,
                  size: 24,
                  color: _getStatusColor(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.direction == TransferDirection.sending
                            ? 'Sending to ${session.peer.name}'
                            : 'Receiving from ${session.peer.name}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Klill',
                        ),
                      ),
                      Text(
                        '${session.peer.address}:${session.peer.port}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontFamily: 'LiberationSans',
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(),
                if (session.status == TransferStatus.inProgress && onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onCancel,
                    tooltip: 'Cancel transfer',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Progress bar
            _buildProgressBar(),
            const SizedBox(height: 8),
            
            // Transfer statistics (only for non-completed transfers)
            if (session.status != TransferStatus.completed)
              Row(
                children: [
                  Expanded(child: _buildTransferStats()),
                  if (session.status == TransferStatus.inProgress)
                    _buildSpeedInfo(),
                ],
              ),
            const SizedBox(height: 12),
            
            // Current file being transferred (only for multi-file transfers)
            if (session.status == TransferStatus.inProgress && !_isFolderTransfer() && !_isSingleFileTransfer())
              _buildCurrentFileInfo(),
            
            // Files list (collapsed by default, expandable)
            if (session.items.isNotEmpty)
              _buildFilesSection(),
            
            // Error information
            if (session.status == TransferStatus.failed && session.error != null)
              _buildErrorSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    // For completed transfers, show a clean summary without progress bar
    if (session.status == TransferStatus.completed) {
      return _buildCompletedSummary();
    }
    
    // For active transfers, show progress bar
    final progress = session.totalSize > 0 
        ? (session.transferredSize / session.totalSize)
        : 0.0;
    
    // Clamp progress to valid range but allow 1.0 when completed
    final displayProgress = progress.clamp(0.0, 1.0);
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_formatSize(session.transferredSize)} / ${_formatSize(session.totalSize)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'LiberationSans',
              ),
            ),
            Text(
              '${(displayProgress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: displayProgress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
          minHeight: 8,
        ),
      ],
    );
  }

  Widget _buildTransferStats() {
    return Row(
      children: [
        Icon(
          Icons.description_outlined,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Text(
          session.totalFiles > 0
              ? '${session.completedFiles}/${session.totalFiles} files'
              : '${session.items.length} ${session.items.length == 1 ? 'item' : 'items'}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontFamily: 'LiberationSans',
          ),
        ),
        const SizedBox(width: 16),
        Icon(
          Icons.access_time,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Text(
          _getElapsedTime(),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontFamily: 'LiberationSans',
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.green[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Transfer completed successfully',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.green[700],
                      fontFamily: 'LiberationSans',
                    ),
                  ),
                ],
              ),
              Text(
                _formatSize(session.totalSize),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 14,
                color: Colors.green[600],
              ),
              const SizedBox(width: 4),
              Text(
                session.totalFiles > 0
                    ? '${session.completedFiles}/${session.totalFiles} files'
                    : '${session.items.length} ${session.items.length == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green[600],
                  fontFamily: 'LiberationSans',
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 14,
                color: Colors.green[600],
              ),
              const SizedBox(width: 4),
              Text(
                _getElapsedTime(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green[600],
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedInfo() {
    final speed = _calculateTransferSpeed();
    final eta = _calculateETA();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              '${_formatSpeed(speed)}/s',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
        if (eta.isFinite && eta > 0)
          Text(
            'ETA: ${_formatDuration(eta)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontFamily: 'LiberationSans',
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentFileInfo() {
    // For folder transfers, show only the folder name, not individual files
    String displayName;
    TransferType displayType = TransferType.file;
    int displaySize = 0;

    // Check if this is a folder transfer
    final folderItem = session.items.firstWhere(
      (item) => item.type == TransferType.folder,
      orElse: () => TransferItem(
        id: '',
        name: '',
        size: 0,
        type: TransferType.file,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
      ),
    );

    if (folderItem.type == TransferType.folder) {
      // For folder transfers, always show the folder name
      displayName = folderItem.name;
      displayType = TransferType.folder;
      displaySize = folderItem.size;
    } else if (session.currentFileName != null && session.currentFileName!.isNotEmpty) {
      // Show current file being transferred (for single file transfers)
      displayName = session.currentFileName!;
      displayType = TransferType.file;
      displaySize = 0;
    } else {
      // Fallback to item logic
      TransferItem? currentItem;
      for (final item in session.items) {
        if (item.status == TransferStatus.inProgress) {
          currentItem = item;
          break;
        }
      }
      
      currentItem ??= session.items.lastWhere(
        (item) => item.status == TransferStatus.completed,
        orElse: () => session.items.first,
      );

      displayName = currentItem.name;
      displayType = currentItem.type;
      displaySize = currentItem.size;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(displayType),
            size: 20,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'LiberationSans',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (displaySize > 0)
                  Text(
                    _formatSize(displaySize),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontFamily: 'LiberationSans',
                    ),
                  ),
                if (session.currentFileName != null && session.totalFiles > 0 && !_isFolderTransfer() && !_isSingleFileTransfer())
                  Text(
                    'File ${session.completedFiles + 1} of ${session.totalFiles}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontFamily: 'LiberationSans',
                    ),
                  ),
              ],
            ),
          ),
          session.currentFileName != null && !_isFolderTransfer() && !_isSingleFileTransfer()
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _buildItemStatus(session.items.isNotEmpty ? session.items.first : TransferItem(
                  id: 'temp',
                  name: 'Unknown',
                  size: 0,
                  type: TransferType.file,
                  status: session.status,
                  createdAt: DateTime.now(),
                )),
        ],
      ),
    );
  }

  Widget _buildFilesSection() {
    // Group items by type and show simplified list
    final folders = session.items.where((item) => item.type == TransferType.folder).toList();
    final files = session.items.where((item) => item.type == TransferType.file).toList();
    final texts = session.items.where((item) => item.type == TransferType.text).toList();
    
    // For folder transfers (any folder present), don't show the dropdown - just show folder name
    if (folders.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.folder,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              _getDisplayFolderName(folders.first.name),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
      );
    }
    
    // For single file transfers, don't show the dropdown - just show file name
    if (files.length == 1 && folders.isEmpty && texts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.description,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                files.first.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                  fontFamily: 'LiberationSans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatSize(files.first.size),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
      );
    }
    
    // For single text transfers, don't show the dropdown - just show text name
    if (texts.length == 1 && folders.isEmpty && files.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.text_snippet,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texts.first.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                  fontFamily: 'LiberationSans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatSize(texts.first.size),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
      );
    }
    
    return ExpansionTile(
      title: Text(
        'Items (${session.items.length})',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'LiberationSans',
        ),
      ),
      children: [
        // Show folders
        if (folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Folders (${folders.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          ...folders.map((item) => ListTile(
            dense: true,
            leading: Icon(
              _getFileIcon(item.type),
              size: 18,
              color: Colors.grey[600],
            ),
            title: Text(
              item.name,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'LiberationSans',
              ),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _buildItemStatus(item),
          )).toList(),
        ],
        
        // Show files (limit to 5 for simplicity)
        if (files.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Files (${files.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          ...files.take(5).map((item) => ListTile(
            dense: true,
            leading: Icon(
              _getFileIcon(item.type),
              size: 18,
              color: Colors.grey[600],
            ),
            title: Text(
              item.name,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'LiberationSans',
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _formatSize(item.size),
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                fontFamily: 'LiberationSans',
              ),
            ),
            trailing: _buildItemStatus(item),
          )).toList(),
          if (files.length > 5)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '... and ${files.length - 5} more files',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                  fontFamily: 'LiberationSans',
                ),
              ),
            ),
        ],
        
        // Show text items
        if (texts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Text (${texts.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          ...texts.map((item) => ListTile(
            dense: true,
            leading: Icon(
              _getFileIcon(item.type),
              size: 18,
              color: Colors.grey[600],
            ),
            title: Text(
              item.name,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'LiberationSans',
              ),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _buildItemStatus(item),
          )).toList(),
        ],
      ],
    );
  }

  Widget _buildItemStatus(TransferItem item) {
    switch (item.status) {
      case TransferStatus.completed:
        return const Icon(Icons.check_circle, size: 16, color: Colors.green);
      case TransferStatus.inProgress:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case TransferStatus.failed:
        return const Icon(Icons.error, size: 16, color: Colors.red);
      default:
        return const Icon(Icons.pending, size: 16, color: Colors.grey);
    }
  }

  Widget _buildErrorSection() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.error!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    String text;
    Color color;
    
    switch (session.status) {
      case TransferStatus.inProgress:
        text = 'In Progress';
        color = Colors.blue;
        break;
      case TransferStatus.completed:
        text = 'Completed';
        color = Colors.green;
        break;
      case TransferStatus.failed:
        text = 'Failed';
        color = Colors.red;
        break;
      case TransferStatus.cancelled:
        text = 'Cancelled';
        color = Colors.orange;
        break;
      default:
        text = 'Pending';
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: session.status == TransferStatus.completed 
            ? Colors.green[100] 
            : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: session.status == TransferStatus.completed 
              ? Colors.green[300]! 
              : color.withOpacity(0.3)
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.status == TransferStatus.completed) ...[
            Icon(
              Icons.check_circle,
              size: 12,
              color: Colors.green[600],
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: session.status == TransferStatus.completed 
                  ? Colors.green[700] 
                  : color,
              fontFamily: 'LiberationSans',
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (session.status) {
      case TransferStatus.inProgress:
        return Colors.blue;
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
        return Colors.red;
      case TransferStatus.cancelled:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getFileIcon(TransferType type) {
    switch (type) {
      case TransferType.text:
        return Icons.text_snippet;
      case TransferType.folder:
        return Icons.folder;
      case TransferType.file:
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B';
    if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB';
    if (bytesPerSecond < 1024 * 1024 * 1024) return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)}m ${(seconds % 60).toStringAsFixed(0)}s';
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }

  String _getElapsedTime() {
    final elapsed = DateTime.now().difference(session.startedAt);
    return _formatDuration(elapsed.inSeconds.toDouble());
  }

  double _calculateTransferSpeed() {
    final elapsed = DateTime.now().difference(session.startedAt);
    if (elapsed.inSeconds == 0) return 0.0;
    
    // Calculate speed in bytes per second
    final speed = session.transferredSize / elapsed.inSeconds;
    
    // Return 0 if speed is too low to be meaningful
    return speed < 1.0 ? 0.0 : speed;
  }

  double _calculateETA() {
    final speed = _calculateTransferSpeed();
    if (speed <= 0 || session.transferredSize >= session.totalSize) return 0.0;
    final remaining = session.totalSize - session.transferredSize;
    return remaining / speed;
  }

  /// Strips the (x) suffix from folder names for display purposes
  /// e.g., "4kw1 (7)" becomes "4kw1"
  String _getDisplayFolderName(String folderName) {
    // Remove pattern like " (7)" at the end of the folder name
    final regex = RegExp(r' \(\d+\)$');
    return folderName.replaceAll(regex, '');
  }
}