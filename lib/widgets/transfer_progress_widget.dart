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
    final theme = Theme.of(context);
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
                  color: _getStatusColor(theme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _getHeaderText(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Klill',
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.computer,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${session.peer.address}:${session.peer.port}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontFamily: 'LiberationSans',
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(theme),
                if ((session.status == TransferStatus.inProgress || session.status == TransferStatus.waitingForAcceptance) && onCancel != null)
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: theme.colorScheme.error),
                    onPressed: onCancel,
                    tooltip: 'Cancel transfer',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Progress bar
            _buildProgressBar(theme),
            const SizedBox(height: 6),
            
            // Transfer statistics (only for active transfers)
            if (session.status == TransferStatus.inProgress)
              Row(
                children: [
                  Expanded(child: _buildTransferStats(theme)),
                  if (session.status == TransferStatus.inProgress)
                    _buildSpeedInfo(theme),
                ],
              ),
            const SizedBox(height: 8),
            
            // Current file being transferred (only for multi-file transfers)
            if (session.status == TransferStatus.inProgress && !_isFolderTransfer() && !_isSingleFileTransfer())
              _buildCurrentFileInfo(theme),
            
            // Files list (collapsed by default, expandable) - Only show for active transfers
            if (session.items.isNotEmpty && session.status == TransferStatus.inProgress)
              _buildFilesSection(theme),
            
            // Error information
            if (session.status == TransferStatus.failed && session.error != null)
              _buildErrorSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    // For completed transfers, show a clean summary without progress bar
    if (session.status == TransferStatus.completed) {
      return _buildCompletedSummary(theme);
    }
    
    // For failed transfers, show a failed summary without progress bar
    if (session.status == TransferStatus.failed) {
      return _buildFailedSummary(theme);
    }
    
    // For cancelled transfers, show a cancelled summary without progress bar
    if (session.status == TransferStatus.cancelled) {
      return _buildCancelledSummary(theme);
    }
    
    // For waiting for acceptance, show a different UI
    if (session.status == TransferStatus.waitingForAcceptance) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(theme)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Waiting for recipient to accept...',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatSize(session.totalSize)} • ${session.totalFiles} ${session.totalFiles == 1 ? 'item' : 'items'}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      );
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'LiberationSans',
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              '${(displayProgress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'LiberationSans',
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: displayProgress,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(theme)),
          minHeight: 8,
        ),
      ],
    );
  }

  Widget _buildTransferStats(ThemeData theme) {
    return Row(
      children: [
        Icon(
          _isFolderTransfer() ? Icons.folder : Icons.description_outlined,
          size: 16,
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
        const SizedBox(width: 4),
        Text(
          _isFolderTransfer()
              ? '1/1 folder'
              : session.totalFiles > 0
                  ? '${session.completedFiles}/${session.totalFiles} files'
                  : '${session.items.length} ${session.items.length == 1 ? 'item' : 'items'}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontFamily: 'LiberationSans',
          ),
        ),
        const SizedBox(width: 16),
        Icon(
          Icons.access_time,
          size: 16,
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
        const SizedBox(width: 4),
        Text(
          _getElapsedTime(),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontFamily: 'LiberationSans',
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedSummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getTransferDescription(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.green.shade700,
                          fontFamily: 'LiberationSans',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatSize(session.totalSize),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                _isFolderTransfer() ? Icons.folder : Icons.description_outlined,
                size: 14,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                _isFolderTransfer()
                    ? '1/1 folder'
                    : session.totalFiles > 0
                        ? '${session.completedFiles}/${session.totalFiles} files'
                        : '${session.items.length} ${session.items.length == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade700,
                  fontFamily: 'LiberationSans',
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 14,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                _getElapsedTime(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade700,
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFailedSummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getTransferDescription(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.error,
                          fontFamily: 'LiberationSans',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatSize(session.totalSize),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _isFolderTransfer() ? Icons.folder : Icons.description_outlined,
                size: 14,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                _isFolderTransfer()
                    ? '0/1 folder'
                    : session.totalFiles > 0
                        ? '${session.completedFiles}/${session.totalFiles} files'
                        : '${session.items.length} ${session.items.length == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                  fontFamily: 'LiberationSans',
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 14,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                _getElapsedTime(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCancelledSummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.cancel_outlined,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getTransferDescription(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.amber.shade700,
                          fontFamily: 'LiberationSans',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatSize(session.totalSize),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade700,
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _isFolderTransfer() ? Icons.folder : Icons.description_outlined,
                size: 14,
                color: Colors.amber.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                _isFolderTransfer()
                    ? '0/1 folder'
                    : session.totalFiles > 0
                        ? '${session.completedFiles}/${session.totalFiles} files'
                        : '${session.items.length} ${session.items.length == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade700,
                  fontFamily: 'LiberationSans',
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 14,
                color: Colors.amber.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                _getElapsedTime(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade700,
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedInfo(ThemeData theme) {
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '${_formatSpeed(speed)}/s',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
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
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'LiberationSans',
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentFileInfo(ThemeData theme) {
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
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(displayType),
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'LiberationSans',
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (displaySize > 0)
                  Text(
                    _formatSize(displaySize),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'LiberationSans',
                    ),
                  ),
                if (session.currentFileName != null && session.totalFiles > 0 && !_isFolderTransfer() && !_isSingleFileTransfer())
                  Text(
                    'File ${session.completedFiles + 1} of ${session.totalFiles}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
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
                ), theme),
        ],
      ),
    );
  }

  Widget _buildFilesSection(ThemeData theme) {
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              _getDisplayFolderName(folders.first.name),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                files.first.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'LiberationSans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatSize(files.first.size),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texts.first.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'LiberationSans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatSize(texts.first.size),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
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
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'LiberationSans',
          color: theme.colorScheme.onSurface,
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
                color: theme.colorScheme.onSurface,
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          ...folders.map((item) => ListTile(
            dense: true,
            leading: Icon(
              _getFileIcon(item.type),
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              item.name,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'LiberationSans',
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _buildItemStatus(item, theme),
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
                color: theme.colorScheme.onSurface,
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          ...files.take(5).map((item) => ListTile(
            dense: true,
            leading: Icon(
              _getFileIcon(item.type),
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              item.name,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'LiberationSans',
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _formatSize(item.size),
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'LiberationSans',
              ),
            ),
            trailing: _buildItemStatus(item, theme),
          )).toList(),
          if (files.length > 5)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '... and ${files.length - 5} more files',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
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
                color: theme.colorScheme.onSurface,
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          ...texts.map((item) => ListTile(
            dense: true,
            leading: Icon(
              _getFileIcon(item.type),
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              item.name,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'LiberationSans',
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _buildItemStatus(item, theme),
          )).toList(),
        ],
      ],
    );
  }

  Widget _buildItemStatus(TransferItem item, ThemeData theme) {
    switch (item.status) {
      case TransferStatus.completed:
        return Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary);
      case TransferStatus.inProgress:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case TransferStatus.failed:
        return Icon(Icons.error, size: 16, color: theme.colorScheme.error);
      default:
        return Icon(Icons.pending, size: 16, color: theme.colorScheme.onSurfaceVariant);
    }
  }

  Widget _buildErrorSection(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.error!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.error,
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    String text;
    Color color = _getStatusColor(theme);
    
    switch (session.status) {
      case TransferStatus.waitingForAcceptance:
        text = 'Waiting for acceptance';
        break;
      case TransferStatus.inProgress:
        text = 'In Progress';
        break;
      case TransferStatus.completed:
        text = 'Completed';
        break;
      case TransferStatus.failed:
        text = 'Failed';
        break;
      case TransferStatus.cancelled:
        text = 'Cancelled';
        break;
      default:
        text = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(theme).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor(theme).withOpacity(0.3)
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.status == TransferStatus.completed) ...[
            Icon(
              Icons.check_circle,
              size: 12,
              color: _getStatusColor(theme),
            ),
            const SizedBox(width: 4),
          ],
          if (session.status == TransferStatus.failed) ...[
            Icon(
              Icons.error_outline,
              size: 12,
              color: _getStatusColor(theme),
            ),
            const SizedBox(width: 4),
          ],
          if (session.status == TransferStatus.cancelled) ...[
            Icon(
              Icons.cancel_outlined,
              size: 12,
              color: _getStatusColor(theme),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _getStatusColor(theme),
              fontFamily: 'LiberationSans',
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ThemeData theme) {
    switch (session.status) {
      case TransferStatus.waitingForAcceptance:
        return theme.colorScheme.secondary;
      case TransferStatus.inProgress:
        return theme.colorScheme.primary;
      case TransferStatus.completed:
        return Colors.green.shade700;
      case TransferStatus.failed:
        return theme.colorScheme.error;
      case TransferStatus.cancelled:
        return Colors.amber.shade700;
      default:
        return theme.colorScheme.onSurfaceVariant;
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
    // Use the speed from the SpeedCalculator system instead of basic calculation
    return session.currentSpeed;
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

  /// Generate a meaningful description of the transferred files/folders
  String _getTransferDescription() {
    if (session.items.isEmpty) {
      if (session.totalFiles > 0) {
        return session.totalFiles == 1 ? '1 file' : '${session.totalFiles} files';
      }
      return 'Transfer completed';
    }

    final files = session.items.where((item) => item.type == TransferType.file).toList();
    final folders = session.items.where((item) => item.type == TransferType.folder).toList();
    final texts = session.items.where((item) => item.type == TransferType.text).toList();

    // For folder transfers, just show the folder name
    if (_isFolderTransfer()) {
      if (folders.isNotEmpty) {
        return _getDisplayFolderName(folders.first.name);
      }
    }

    List<String> parts = [];

    // Handle single items first for better display
    if (session.items.length == 1) {
      final item = session.items.first;
      switch (item.type) {
        case TransferType.file:
          return item.name;
        case TransferType.folder:
          return _getDisplayFolderName(item.name);
        case TransferType.text:
          return 'Text message';
      }
    }

    // Handle multiple items - show actual file names instead of counts
    if (files.length == 1) {
      parts.add(files.first.name);
    } else if (files.length > 1) {
      // Show first file name + additional count: "filename.txt +5 files"
      final firstName = files.first.name;
      final additionalCount = files.length - 1;
      parts.add('$firstName +$additionalCount files');
    }

    if (folders.length == 1) {
      parts.add(_getDisplayFolderName(folders.first.name));
    } else if (folders.length > 1) {
      // Show first folder name + additional count: "foldername +2 folders"
      final firstName = _getDisplayFolderName(folders.first.name);
      final additionalCount = folders.length - 1;
      parts.add('$firstName +$additionalCount folders');
    }

    if (texts.isNotEmpty) {
      parts.add('text');
    }

    if (parts.isEmpty) {
      return 'Transfer completed';
    } else if (parts.length == 1) {
      return parts.first;
    } else if (parts.length == 2) {
      return '${parts[0]} and ${parts[1]}';
    } else {
      return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
    }
  }

  /// Get the header text based on transfer status and direction
  String _getHeaderText() {
    final isCompleted = session.status == TransferStatus.completed || 
                       session.status == TransferStatus.failed ||
                       session.status == TransferStatus.cancelled;
    
    final hostName = _extractHostname(session.peer.name);
    
    if (session.direction == TransferDirection.sending) {
      if (isCompleted) {
        return 'Sent to $hostName';
      } else {
        return 'Sending to $hostName';
      }
    } else {
      if (isCompleted) {
        return 'Received from $hostName';
      } else {
        return 'Receiving from $hostName';
      }
    }
  }

  String _extractHostname(String displayName) {
    // Extract hostname from formats like "Username at Hostname (Platform)" or "Hostname (Platform)"
    if (displayName.contains(' at ')) {
      // Format: "Username at Hostname (Platform)"
      final parts = displayName.split(' at ');
      if (parts.length > 1) {
        final hostnamePart = parts[1];
        // Remove platform info if present: "Hostname (Platform)" -> "Hostname"
        if (hostnamePart.contains(' (')) {
          return hostnamePart.split(' (')[0];
        }
        return hostnamePart;
      }
    } else if (displayName.contains(' (')) {
      // Format: "Hostname (Platform)"
      return displayName.split(' (')[0];
    }
    return displayName;
  }

}
