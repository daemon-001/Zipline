import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/peer.dart';

class TransferRequestDialog extends StatefulWidget {
  final Map<String, dynamic> requestData;
  final String? currentSaveLocation;
  final Function(bool accept, String? saveLocation, bool remember, String? reason) onResponse;

  const TransferRequestDialog({
    super.key,
    required this.requestData,
    required this.onResponse,
    this.currentSaveLocation,
  });

  @override
  State<TransferRequestDialog> createState() => _TransferRequestDialogState();
}

class _TransferRequestDialogState extends State<TransferRequestDialog> {
  String? _selectedSaveLocation;
  bool _rememberLocation = false;
  bool _isSelectingLocation = false;
  
  @override
  void initState() {
    super.initState();
    _selectedSaveLocation = widget.currentSaveLocation;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  Future<void> _selectSaveLocation() async {
    setState(() {
      _isSelectingLocation = true;
    });

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose save location',
        initialDirectory: _selectedSaveLocation,
      );

      if (selectedDirectory != null) {
        setState(() {
          _selectedSaveLocation = selectedDirectory;
        });
      }
    } catch (e) {
      // Handle error silently or show a snackbar
    } finally {
      setState(() {
        _isSelectingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final senderPeer = widget.requestData['senderPeer'] as Peer;
    final totalFiles = widget.requestData['totalFiles'] as int;
    final totalSize = widget.requestData['totalSize'] as int;
    final description = widget.requestData['description'] as String?;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.file_download_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Incoming Transfer'),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      senderPeer.name.isNotEmpty ? senderPeer.name[0].toUpperCase() : 'U',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          senderPeer.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${senderPeer.address} • ${senderPeer.connectionType}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Transfer details
            Text(
              'Transfer Details',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Size: ${_formatFileSize(totalSize)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
                Text(
                  '$totalFiles ${totalFiles == 1 ? 'item' : 'items'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (description != null && description.isNotEmpty) ...[
              Text(
                'Description: $description',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Save location selection
            Text(
              'Save Location',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedSaveLocation ?? 'No location selected',
                      style: TextStyle(
                        color: _selectedSaveLocation != null 
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _isSelectingLocation ? null : _selectSaveLocation,
                    icon: _isSelectingLocation
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.folder_open, size: 16),
                    label: const Text('Browse'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Remember location checkbox
            CheckboxListTile(
              value: _rememberLocation,
              onChanged: (value) {
                setState(() {
                  _rememberLocation = value ?? false;
                });
              },
              title: Text(
                'Set as Default location',
                style: const TextStyle(fontSize: 14),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => widget.onResponse(false, null, false, 'User declined'),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: _selectedSaveLocation != null
              ? () => widget.onResponse(
                    true, 
                    _selectedSaveLocation,
                    _rememberLocation,
                    null,
                  )
              : null,
          child: const Text('Accept'),
        ),
      ],
    );
  }
}