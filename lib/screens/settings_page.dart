import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../providers/app_state_provider.dart';
import '../services/file_transfer_service.dart';
import '../models/app_settings.dart';
import '../utils/system_info.dart';
import '../widgets/top_notification.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const SettingsPage({super.key, required this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _nameController;
  late TextEditingController _pathController;
  bool _showNotifications = true;
  bool _startMinimized = false;
  AppTheme _selectedTheme = AppTheme.system;
  String? _diagnosticsResult;
  bool _isSaving = false;
  
  // Original values for change detection
  late String _originalName;
  late String _originalPath;
  late bool _originalShowNotifications;
  late bool _originalStartMinimized;
  late AppTheme _originalTheme;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<AppStateProvider>(context, listen: false).settings;
    
    // Initialize current values
    final name = settings?.buddyName ?? SystemInfo.getSystemHostname();
    final path = settings?.destPath ?? '';
    _showNotifications = settings?.showNotifications ?? true;
    _startMinimized = settings?.startMinimized ?? false;
    _selectedTheme = settings?.theme ?? AppTheme.system;
    
    _nameController = TextEditingController(text: name);
    _pathController = TextEditingController(text: path);
    
    // Store original values
    _originalName = name;
    _originalPath = path;
    _originalShowNotifications = _showNotifications;
    _originalStartMinimized = _startMinimized;
    _originalTheme = _selectedTheme;
    
    // Add listeners for change detection
    _nameController.addListener(_checkForChanges);
    _pathController.addListener(_checkForChanges);
    
    _initializeDefaultPath();
  }

  void _checkForChanges() {
    setState(() {
      // This will trigger a rebuild and update the floating action button visibility
    });
  }

  bool get _hasChanges {
    return _nameController.text != _originalName ||
           _pathController.text != _originalPath ||
           _showNotifications != _originalShowNotifications ||
           _startMinimized != _originalStartMinimized ||
           _selectedTheme != _originalTheme;
  }

  Future<void> _initializeDefaultPath() async {
    if (_pathController.text.isEmpty) {
      try {
        final downloadsDir = await getDownloadsDirectory();
        setState(() {
          _pathController.text = downloadsDir?.path ?? '';
          _originalPath = _pathController.text; // Update original path
        });
      } catch (e) {
        // Fallback to documents directory
        try {
          final documentsDir = await getApplicationDocumentsDirectory();
          setState(() {
            _pathController.text = documentsDir.path;
            _originalPath = _pathController.text; // Update original path
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
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // Header with modern styling
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: widget.onBack,
                      icon: Icon(Icons.arrow_back, color: theme.colorScheme.onPrimary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Klill',
                          ),
                        ),
                        Text(
                          'Configure your Zipline experience',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontFamily: 'LiberationSans',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.settings,
                      color: theme.colorScheme.onPrimary,
                      size: 24,
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
                    _buildThemeSelector(),
                    _buildSwitchTile(
                      'Show Notifications',
                      'Display notifications for transfers',
                      _showNotifications,
                      (value) {
                        setState(() => _showNotifications = value);
                        _checkForChanges();
                      },
                    ),
                    _buildSwitchTile(
                      'Start Minimized',
                      'Start the app in system tray',
                      _startMinimized,
                      (value) {
                        setState(() => _startMinimized = value);
                        _checkForChanges();
                      },
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
                
                // Network Diagnostics section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.surface,
                        theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.network_check,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Network Diagnostics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                              fontFamily: 'Klill',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _runNetworkDiagnostics,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Run Network Test'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (_diagnosticsResult != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _diagnosticsResult!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: theme.colorScheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 80), // Extra space for floating action button
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _hasChanges ? FloatingActionButton(
        onPressed: _isSaving ? null : _saveSettings,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 6,
        tooltip: _isSaving ? 'Saving...' : 'Save Settings',
        child: _isSaving
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                ),
              )
            : const Icon(Icons.check, size: 24),
      ) : null,
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getSectionIcon(title),
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Klill',
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  IconData _getSectionIcon(String title) {
    switch (title) {
      case 'User Settings':
        return Icons.person_outline;
      case 'Network Settings':
        return Icons.wifi_outlined;
      case 'File Settings':
        return Icons.folder_outlined;
      case 'App Settings':
        return Icons.palette_outlined;
      case 'History Management':
        return Icons.history;
      default:
        return Icons.settings_outlined;
    }
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(
          fontFamily: 'LiberationSans',
          color: theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(
            fontFamily: 'Klill',
            fontWeight: FontWeight.w500,
          ),
          hintStyle: TextStyle(
            fontFamily: 'LiberationSans',
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 2,
            ),
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildPathField() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _pathController,
              style: TextStyle(
                fontFamily: 'LiberationSans',
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                labelText: 'Download Path',
                hintText: 'Where received files will be saved',
                labelStyle: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  fontFamily: 'LiberationSans',
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _browseForFolder,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Browse'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'Klill',
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AppTheme>(
            value: _selectedTheme,
            style: TextStyle(
              fontFamily: 'LiberationSans',
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            items: AppTheme.values.map((AppTheme themeValue) {
              return DropdownMenuItem<AppTheme>(
                value: themeValue,
                child: Text(
                  _getThemeDisplayName(themeValue),
                  style: TextStyle(
                    fontFamily: 'LiberationSans',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              );
            }).toList(),
            onChanged: (AppTheme? newTheme) {
              if (newTheme != null) {
                setState(() {
                  _selectedTheme = newTheme;
                });
                _checkForChanges();
              }
            },
          ),
        ],
      ),
    );
  }

  String _getThemeDisplayName(AppTheme theme) {
    switch (theme) {
      case AppTheme.light:
        return 'Light Mode';
      case AppTheme.dark:
        return 'Dark Mode';
      case AppTheme.system:
        return 'System Default';
    }
  }


  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Klill',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'LiberationSans',
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: theme.colorScheme.primary,
          ),
        ],
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
        _checkForChanges();
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
          title: 'Folder Selection Error',
          message: 'Error selecting folder: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  void _saveSettings() async {
    if (_isSaving) return;
    
    setState(() {
      _isSaving = true;
    });
    
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    
    // Validate buddy name
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _isSaving = false;
      });
      TopNotification.show(
        context,
        title: 'Missing Buddy Name',
        message: 'Please enter a buddy name',
        type: NotificationType.error,
      );
      return;
    }
    
    // Simulate save delay for better UX
    await Future.delayed(const Duration(milliseconds: 800));
    
    final currentSettings = appState.settings ?? AppSettings(
      buddyName: SystemInfo.getSystemHostname(),
      destPath: '',
    );
    
    final newSettings = currentSettings.copyWith(
      buddyName: _nameController.text.trim(),
      destPath: _pathController.text.trim(),
      showNotifications: _showNotifications,
      startMinimized: _startMinimized,
      theme: _selectedTheme,
    );
    
    appState.updateSettings(newSettings);
    
    setState(() {
      _isSaving = false;
    });
    
    if (mounted) {
      TopNotification.show(
        context,
        title: 'Settings Saved',
        message: 'Your settings have been saved successfully',
        type: NotificationType.success,
      );
      
      // Go back after saving
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          widget.onBack();
        }
      });
    }
  }

  Widget _buildHistoryTile() {
    final theme = Theme.of(context);
    return Consumer<FileTransferService>(
      builder: (context, fileTransfer, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.history,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transfer History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Klill',
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fileTransfer.historyCount} completed transfers',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'LiberationSans',
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: fileTransfer.historyCount > 0 ? _clearHistory : null,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear All'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _clearHistory() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 8,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.3),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                theme.colorScheme.errorContainer.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.delete_forever,
                  color: theme.colorScheme.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Clear Transfer History',
                  style: TextStyle(
                    fontFamily: 'Klill',
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to clear all transfer history?',
              style: TextStyle(
                fontFamily: 'LiberationSans',
                fontSize: 16,
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.error,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: TextStyle(
                        fontFamily: 'LiberationSans',
                        fontSize: 12,
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () {
              Provider.of<FileTransferService>(context, listen: false).clearHistory();
              Navigator.of(context).pop();
              TopNotification.show(
                context,
                title: 'History Cleared',
                message: 'Transfer history has been cleared',
                type: NotificationType.success,
              );
            },
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Clear History'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
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

  Future<void> _runNetworkDiagnostics() async {
    setState(() {
      _diagnosticsResult = 'Running diagnostics...';
    });

    try {
      final fileTransfer = Provider.of<FileTransferService>(context, listen: false);
      final diagnostics = await fileTransfer.getNetworkDiagnostics();
      
      final buffer = StringBuffer();
      buffer.writeln('=== Network Diagnostics ===');
      
      diagnostics.forEach((key, value) {
        if (key == 'local_ips' && value is List) {
          buffer.writeln('Local IP Addresses:');
          for (final ip in value) {
            buffer.writeln('  • $ip');
          }
        } else {
          buffer.writeln('$key: $value');
        }
      });
      
      buffer.writeln('\n=== Troubleshooting Tips ===');
      buffer.writeln('• Make sure Windows Firewall allows Zipline on port 6442');
      buffer.writeln('• Ensure both devices are on the same network');
      buffer.writeln('• Try disabling antivirus temporarily if transfers fail');
      buffer.writeln('• Check if target device has Zipline running');
      
      setState(() {
        _diagnosticsResult = buffer.toString();
      });
    } catch (e) {
      setState(() {
        _diagnosticsResult = 'Error running diagnostics: $e';
      });
    }
  }
}