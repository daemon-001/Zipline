import 'dart:io';

class SystemInfo {
  static String? _cachedUsername;
  static String? _cachedHostname;
  static String? _cachedPlatform;

  /// Get the system username
  static String getSystemUsername() {
    if (_cachedUsername != null) return _cachedUsername!;

    // Try USERNAME first (Windows), then USER (Unix-like)
    String? username = Platform.environment['USERNAME'] ?? 
                      Platform.environment['USER'];
    
    if (username == null || username.isEmpty) {
      username = 'Unknown';
    } else {
      // Capitalize first letter
      username = username[0].toUpperCase() + username.substring(1).toLowerCase();
    }
    
    _cachedUsername = username;
    return username;
  }

  /// Get the system hostname
  static String getSystemHostname() {
    if (_cachedHostname != null) return _cachedHostname!;

    String? hostname = Platform.environment['COMPUTERNAME'] ?? 
                      Platform.environment['HOSTNAME'];
    
    if (hostname == null || hostname.isEmpty) {
      hostname = 'Unknown-Host';
    } else {
      // Remove .local suffix if present (macOS)
      hostname = hostname.replaceAll('.local', '');
    }
    
    _cachedHostname = hostname;
    return hostname;
  }

  /// Get the platform name
  static String getPlatformName() {
    if (_cachedPlatform != null) return _cachedPlatform!;

    if (Platform.isWindows) {
      _cachedPlatform = 'Windows';
    } else if (Platform.isMacOS) {
      _cachedPlatform = 'Macintosh';
    } else if (Platform.isLinux) {
      _cachedPlatform = 'Linux';
    } else if (Platform.isAndroid) {
      _cachedPlatform = 'Android';
    } else if (Platform.isIOS) {
      _cachedPlatform = 'iOS';
    } else {
      _cachedPlatform = 'Unknown';
    }
    
    return _cachedPlatform!;
  }

  /// Generate the system signature: "Hostname (Platform)"
  static String getSystemSignature() {
    return '${getSystemHostname()} (${getPlatformName()})';
  }

  /// Get the username with device name override
  static String getUsername([String? deviceName]) {
    if (deviceName != null && deviceName.isNotEmpty) {
      return deviceName;
    }
    return getSystemUsername();
  }

  /// Clear cached values
  static void clearCache() {
    _cachedUsername = null;
    _cachedHostname = null;
    _cachedPlatform = null;
  }
}