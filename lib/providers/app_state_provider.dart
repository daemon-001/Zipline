import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';

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

  void initializeSettings() async {
    try {
      // Set default download path to Downloads/Zipline
      final downloadsPath = Platform.isWindows 
          ? '${Platform.environment['USERPROFILE']}\\Downloads\\Zipline' 
          : '${Platform.environment['HOME']}/Downloads/Zipline';
      
      // Load default settings
      _settings = AppSettings(
        buddyName: 'Zipline User',
        destPath: downloadsPath,
      );
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize settings: $e';
      notifyListeners();
    }
  }
}