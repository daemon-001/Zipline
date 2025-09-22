import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../utils/system_info.dart';

class AppStateProvider extends ChangeNotifier {
  static const String _settingsKey = 'zipline_app_settings';
  
  AppSettings? _settings;
  bool _isInitialized = false;
  String? _errorMessage;
  SharedPreferences? _prefs;

  AppSettings? get settings => _settings;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  void setInitialized(bool initialized) {
    _isInitialized = initialized;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  void updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    await _saveSettings();
  }

  void updateTheme(AppTheme theme) async {
    if (_settings != null) {
      _settings = _settings!.copyWith(theme: theme);
      notifyListeners();
      await _saveSettings();
    }
  }

  void initializeSettings() async {
    try {
      // Initialize SharedPreferences
      _prefs = await SharedPreferences.getInstance();
      
      // Try to load existing settings
      final savedSettingsJson = _prefs?.getString(_settingsKey);
      if (savedSettingsJson != null && savedSettingsJson.isNotEmpty) {
        try {
          final settingsMap = jsonDecode(savedSettingsJson) as Map<String, dynamic>;
          _settings = AppSettings.fromJson(settingsMap);
          _isInitialized = true;
          notifyListeners();
          return;
        } catch (e) {
          // If parsing fails, continue to create default settings
        }
      }
      
      // Create default settings if none exist
      String downloadsPath;
      if (Platform.isWindows) {
        downloadsPath = Platform.environment['USERPROFILE'] ?? 
                       'C:\\Users\\User\\Downloads\\Zipline';
        if (!downloadsPath.endsWith('\\Zipline')) {
          downloadsPath = '$downloadsPath\\Downloads\\Zipline';
        }
      } else {
        downloadsPath = Platform.environment['HOME'] ?? 
                       Platform.environment['USERPROFILE'] ?? 
                       '/home/user/Downloads/Zipline';
        if (!downloadsPath.endsWith('/Zipline')) {
          downloadsPath = '$downloadsPath/Downloads/Zipline';
        }
      }
      
      // Create and save default settings
      _settings = AppSettings(
        buddyName: SystemInfo.getSystemHostname(), // Use device name as default
        destPath: downloadsPath,
      );
      
      await _saveSettings();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      // Provide fallback settings instead of failing
      _settings = AppSettings(
        buddyName: SystemInfo.getSystemHostname(), // Use device name as fallback
        destPath: Platform.isWindows ? 'C:\\Downloads\\Zipline' : '/home/user/Downloads/Zipline',
      );
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  Future<void> _saveSettings() async {
    if (_settings != null && _prefs != null) {
      try {
        final settingsJson = jsonEncode(_settings!.toJson());
        await _prefs!.setString(_settingsKey, settingsJson);
      } catch (e) {
        // Handle save error silently - don't block the UI
      }
    }
  }
}