import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/peer.dart';
import '../services/file_transfer_service.dart';

class SendPage extends StatefulWidget {
  final Peer peer;

  const SendPage({super.key, required this.peer});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isTextMode = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Send to ${widget.peer.displayName}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Peer info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          widget.peer.name.isNotEmpty
                              ? widget.peer.name.substring(0, 1).toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.peer.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${widget.peer.address}:${widget.peer.port}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (widget.peer.platform != null)
                            Text(
                              widget.peer.platform!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Mode selector
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Files'),
                  icon: Icon(Icons.folder),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Text'),
                  icon: Icon(Icons.text_fields),
                ),
              ],
              selected: {_isTextMode},
              onSelectionChanged: (Set<bool> newSelection) {
                setState(() {
                  _isTextMode = newSelection.first;
                });
              },
            ),
            
            const SizedBox(height: 24),
            
            // Content area
            Expanded(
              child: _isTextMode ? _buildTextMode() : _buildFileMode(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter text to send:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _textController,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              hintText: 'Type your message here...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _sendText,
                child: const Text('Send Text'),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _pasteFromClipboard,
              child: const Text('Paste'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select files to send:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Icon(
                    Icons.cloud_upload,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Drag and drop files here\nor click the buttons below',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.file_present),
                label: const Text('Select Files'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder),
                label: const Text('Select Folder'),
              ),
            ),
          ],
        ),
      ],
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
      final sessionId = await fileTransfer.sendFiles(
        peer: widget.peer,
        filePaths: filePaths,
      );
      
      if (sessionId != null) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File transfer started'),
              backgroundColor: Colors.green,
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

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('Please enter some text to send');
      return;
    }

    final fileTransfer = Provider.of<FileTransferService>(context, listen: false);
    
    try {
      final sessionId = await fileTransfer.sendText(
        peer: widget.peer,
        text: text,
      );
      
      if (sessionId != null) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text sent successfully'),
              backgroundColor: Colors.green,
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}