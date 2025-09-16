import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../providers/app_state_provider.dart';
import '../services/file_transfer_service.dart';
import '../main.dart';
import '../models/app_settings.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const SettingsPage({super.key, required this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _nameController;
  late TextEditingController _portController;
  late TextEditingController _pathController;
  bool _showNotifications = true;
  bool _startMinimized = false;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<AppStateProvider>(context, listen: false).settings;
    _nameController = TextEditingController(text: settings?.buddyName ?? 'Zipline User');
    _portController = TextEditingController(text: settings?.port.toString() ?? '7250');
    _pathController = TextEditingController(text: settings?.destPath ?? '');
    _showNotifications = settings?.showNotifications ?? true;
    _startMinimized = settings?.startMinimized ?? false;
    
    _initializeDefaultPath();
  }

  Future<void> _initializeDefaultPath() async {
    if (_pathController.text.isEmpty) {
      try {
        final downloadsDir = await getDownloadsDirectory();
        setState(() {
          _pathController.text = downloadsDir?.path ?? '';
        });
      } catch (e) {
        // Fallback to documents directory
        try {
          final documentsDir = await getApplicationDocumentsDirectory();
          setState(() {
            _pathController.text = documentsDir.path;
          });
        } catch (e) {
          // Keep empty if both fail
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Klill',
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Settings content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User settings
                _buildSection(
                  'User Settings',
                  [
                    _buildTextField(
                      'Buddy Name',
                      _nameController,
                      'Your name visible to others',
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Network settings
                _buildSection(
                  'Network Settings',
                  [
                    _buildTextField(
                      'Port',
                      _portController,
                      'Network port for communication',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // File settings
                _buildSection(
                  'File Settings',
                  [
                    _buildPathField(),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // App settings
                _buildSection(
                  'App Settings',
                  [
                    _buildSwitchTile(
                      'Show Notifications',
                      'Display notifications for transfers',
                      _showNotifications,
                      (value) => setState(() => _showNotifications = value),
                    ),
                    _buildSwitchTile(
                      'Start Minimized',
                      'Start the app in system tray',
                      _startMinimized,
                      (value) => setState(() => _startMinimized = value),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // History management
                _buildSection(
                  'History Management',
                  [
                    _buildHistoryTile(),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Save Settings'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Klill',
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildPathField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Download Path',
                hintText: 'Where received files will be saved',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _browseForFolder,
            child: const Text('Browse'),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  void _browseForFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Download Directory',
        initialDirectory: _pathController.text.isNotEmpty 
            ? _pathController.text 
            : Platform.isWindows 
                ? '${Platform.environment['USERPROFILE']}\\Downloads' 
                : '${Platform.environment['HOME']}/Downloads',
      );
      
      if (selectedDirectory != null) {
        setState(() {
          _pathController.text = selectedDirectory;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting folder: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _saveSettings() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    
    // Validate port
    final port = int.tryParse(_portController.text);
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid port number (1-65535)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Validate buddy name
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a buddy name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final currentSettings = appState.settings ?? const AppSettings(
      buddyName: 'Zipline User',
      destPath: '',
    );
    
    final newSettings = currentSettings.copyWith(
      buddyName: _nameController.text.trim(),
      port: port,
      destPath: _pathController.text.trim(),
      showNotifications: _showNotifications,
      startMinimized: _startMinimized,
    );
    
    appState.updateSettings(newSettings);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: Colors.green,
      ),
    );
    
    // Go back after saving
    Future.delayed(const Duration(milliseconds: 500), () {
      widget.onBack();
    });
  }

  Widget _buildHistoryTile() {
    return Consumer<FileTransferService>(
      builder: (context, fileTransfer, child) {
        return ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Transfer History'),
          subtitle: Text('${fileTransfer.historyCount} completed transfers'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: fileTransfer.historyCount > 0 ? _clearHistory : null,
                child: const Text('Clear All'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _clearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Transfer History'),
        content: const Text('Are you sure you want to clear all transfer history? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<FileTransferService>(context, listen: false).clearHistory();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Transfer history cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}