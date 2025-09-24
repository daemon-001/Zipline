import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

class ProfileImageService {
  static ProfileImageService? _instance;
  static ProfileImageService get instance => _instance ??= ProfileImageService._();
  
  ProfileImageService._();

  Uint8List? _cachedAvatar;
  String? _cachedUsername;

  /// Get the user's profile image
  Future<Uint8List?> getProfileImage() async {
    final username = await _getSystemUsername();
    
    // Return cached image if username hasn't changed
    if (_cachedAvatar != null && _cachedUsername == username) {
      return _cachedAvatar;
    }

    // Try to load user-specified avatar first
    final userAvatar = await _loadUserAvatar();
    if (userAvatar != null) {
      _cachedAvatar = userAvatar;
      _cachedUsername = username;
      return userAvatar;
    }

    // Try to load system avatar
    final systemAvatar = await _loadSystemAvatar();
    if (systemAvatar != null) {
      _cachedAvatar = systemAvatar;
      _cachedUsername = username;
      return systemAvatar;
    }

    // Generate fallback avatar with user initial
    final fallbackAvatar = await _generateFallbackAvatar(username);
    _cachedAvatar = fallbackAvatar;
    _cachedUsername = username;
    return fallbackAvatar;
  }

  /// Load user-specified avatar
  Future<Uint8List?> _loadUserAvatar() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final avatarFile = File('${appDir.path}/avatar.png');
      
      if (await avatarFile.exists()) {
        final bytes = await avatarFile.readAsBytes();
        return _processImage(bytes);
      }
    } catch (e) {
    }
    return null;
  }

  /// Load system avatar following Windows approach
  Future<Uint8List?> _loadSystemAvatar() async {
    if (!Platform.isWindows) return null;

    try {
      final username = await _getSystemUsername();
      final localAppData = Platform.environment['LOCALAPPDATA'];
      final programData = Platform.environment['PROGRAMDATA'];
      final allUsersProfile = Platform.environment['ALLUSERSPROFILE'];
      final appData = Platform.environment['APPDATA'];

      if (localAppData == null || programData == null || allUsersProfile == null || appData == null) {
        return null;
      }

      // Try different Windows avatar locations
      final possiblePaths = [
        '$localAppData\\Temp\\$username.bmp',
        '$programData\\Microsoft\\User Account Pictures\\Guest.bmp',
        '$allUsersProfile\\${_getAppDataDirName(appData)}\\Microsoft\\User Account Pictures\\$username.bmp',
        '$allUsersProfile\\${_getAppDataDirName(appData)}\\Microsoft\\User Account Pictures\\Guest.bmp',
      ];

      for (final path in possiblePaths) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          return _processImage(bytes);
        }
      }
    } catch (e) {
    }
    return null;
  }

  /// Generate fallback avatar with user initial
  Future<Uint8List> _generateFallbackAvatar(String username) async {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';
    
    // Create a 64x64 image with gradient background and initial
    final image = img.Image(width: 64, height: 64);
    
    // Fill with gradient background
    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        final color = _getGradientColor(x, y, 64, 64);
        image.setPixel(x, y, color);
      }
    }

    // Add initial text in the center
    final textColor = img.ColorRgb8(255, 255, 255); // White text
    
    // Simple text rendering (you might want to use a proper font rendering library)
    _drawText(image, initial, 32 - (initial.length * 8), 32 - 16, textColor);

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Process and scale image to 64x64
  Uint8List _processImage(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;

      // Scale to 64x64 with smooth transformation
      final scaled = img.copyResize(image, width: 64, height: 64);
      return Uint8List.fromList(img.encodePng(scaled));
    } catch (e) {
      return imageBytes;
    }
  }

  /// Get system username
  Future<String> _getSystemUsername() async {
    final username = Platform.environment['USERNAME'] ?? 
                    Platform.environment['USER'] ?? 
                    'User';
    return username.replaceAll('\\', '+');
  }

  /// Get app data directory name
  String _getAppDataDirName(String appData) {
    final parts = appData.split(Platform.pathSeparator);
    return parts.isNotEmpty ? parts.last : 'Default';
  }

  /// Get gradient color for fallback avatar
  img.ColorRgb8 _getGradientColor(int x, int y, int width, int height) {
    // Create a gradient from top-left to bottom-right
    final progress = (x + y) / (width + height);
    final r = (0x21 + (0x96 - 0x21) * progress).round();
    final g = (0x96 + (0xF3 - 0x96) * progress).round();
    final b = (0xF3 + (0x21 - 0xF3) * progress).round();
    
    return img.ColorRgb8(r, g, b);
  }

  /// Simple text drawing (basic implementation)
  void _drawText(img.Image image, String text, int x, int y, img.ColorRgb8 color) {
    // Basic text rendering
    // In a real implementation, you'd use a proper font rendering library
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final charX = x + (i * 16);
      
      // Draw a simple character representation
      _drawChar(image, char, charX, y, color);
    }
  }

  /// Draw a simple character (basic implementation)
  void _drawChar(img.Image image, String char, int x, int y, img.ColorRgb8 color) {
    // Basic character drawing
    // In a real implementation, you'd use proper font rendering
    for (int dy = 0; dy < 16; dy++) {
      for (int dx = 0; dx < 12; dx++) {
        if (x + dx >= 0 && x + dx < image.width && y + dy >= 0 && y + dy < image.height) {
          image.setPixel(x + dx, y + dy, color);
        }
      }
    }
  }

  /// Clear cached avatar
  void clearCache() {
    _cachedAvatar = null;
    _cachedUsername = null;
  }
}
