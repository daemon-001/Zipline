import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../utils/system_info.dart';

class AppStateProvider extends ChangeNotifier {
  AppSettings? _settings;
  bool _isInitialized = false;
  String? _errorMessage;

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

  void updateSettings(AppSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  void updateTheme(AppTheme theme) {
    if (_settings != null) {
      _settings = _settings!.copyWith(theme: theme);
      notifyListeners();
    }
  }

  void initializeSettings() async {
    try {
      // Set default download path to Downloads/Zipline with fallbacks
      String downloadsPath;
      if (Platform.isWindows) {
        downloadsPath = Platform.environment['USERPROFILE'] ?? 
                       'C:\\Users\\User\\Downloads\\Zipline';
        if (!downloadsPath.endsWith('\\Zipline')) {
          downloadsPath = '$downloadsPath\\Zipline';
        }
      } else {
        downloadsPath = Platform.environment['HOME'] ?? 
                       Platform.environment['USERPROFILE'] ?? 
                       '/home/user/Downloads/Zipline';
        if (!downloadsPath.endsWith('/Zipline')) {
          downloadsPath = '$downloadsPath/Zipline';
        }
      }
      
      // Load default settings with proper system info and fallbacks
      _settings = AppSettings(
        buddyName: SystemInfo.getSystemSignature(),
        destPath: downloadsPath,
      );
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      // Provide fallback settings instead of failing
      _settings = AppSettings(
        buddyName: 'User at Computer',
        destPath: Platform.isWindows ? 'C:\\Downloads\\Zipline' : '/home/user/Downloads/Zipline',
      );
      _isInitialized = true;
      notifyListeners();
    }
  }
}