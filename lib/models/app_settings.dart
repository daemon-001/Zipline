import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import '../utils/system_info.dart';

// part 'app_settings.g.dart';

enum AppTheme {
  light,
  dark,
  system,
}

@JsonSerializable()
class AppSettings {
  final String buddyName;
  final String buddyAvatar;
  final String destPath;
  final bool showNotifications;
  final bool startMinimized;
  final bool showTermsOnStart;
  final String themeColor;
  final AppTheme theme;
  final bool autoStartOnBoot;

  const AppSettings({
    required this.buddyName,
    this.buddyAvatar = '',
    required this.destPath,
    this.showNotifications = true,
    this.startMinimized = false,
    this.showTermsOnStart = true,
    this.themeColor = '#3498db',
    this.theme = AppTheme.system,
    this.autoStartOnBoot = false,
  });

  // Getter for compatibility with optimized services
  String get downloadDirectory => destPath;

  // Fixed port value - cannot be changed by user
  static int get port => 6442;

  // Get the actual brightness based on theme setting
  Brightness get brightness {
    switch (theme) {
      case AppTheme.light:
        return Brightness.light;
      case AppTheme.dark:
        return Brightness.dark;
      case AppTheme.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  // factory AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);
  // Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      buddyName: json['buddyName'] as String,
      buddyAvatar: json['buddyAvatar'] as String? ?? '',
      destPath: json['destPath'] as String,
      // Port is now fixed at 6442, ignore any saved port value
      showNotifications: json['showNotifications'] as bool? ?? true,
      startMinimized: json['startMinimized'] as bool? ?? false,
      showTermsOnStart: json['showTermsOnStart'] as bool? ?? true,
      themeColor: json['themeColor'] as String? ?? '#3498db',
      theme: AppTheme.values.firstWhere(
        (e) => e.name == json['theme'],
        orElse: () => AppTheme.system,
      ),
      autoStartOnBoot: json['autoStartOnBoot'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buddyName': buddyName,
      'buddyAvatar': buddyAvatar,
      'destPath': destPath,
      'showNotifications': showNotifications,
      'startMinimized': startMinimized,
      'showTermsOnStart': showTermsOnStart,
      'themeColor': themeColor,
      'theme': theme.name,
      'autoStartOnBoot': autoStartOnBoot,
    };
  }

  AppSettings copyWith({
    String? buddyName,
    String? buddyAvatar,
    String? destPath,
    String? downloadDirectory, // Alias for destPath
    bool? showNotifications,
    bool? startMinimized,
    bool? showTermsOnStart,
    String? themeColor,
    AppTheme? theme,
    bool? autoStartOnBoot,
  }) {
    return AppSettings(
      buddyName: buddyName ?? this.buddyName,
      buddyAvatar: buddyAvatar ?? this.buddyAvatar,
      destPath: destPath ?? downloadDirectory ?? this.destPath,
      showNotifications: showNotifications ?? this.showNotifications,
      startMinimized: startMinimized ?? this.startMinimized,
      showTermsOnStart: showTermsOnStart ?? this.showTermsOnStart,
      themeColor: themeColor ?? this.themeColor,
      theme: theme ?? this.theme,
      autoStartOnBoot: autoStartOnBoot ?? this.autoStartOnBoot,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          buddyName == other.buddyName &&
          buddyAvatar == other.buddyAvatar &&
          destPath == other.destPath &&
          showNotifications == other.showNotifications &&
          startMinimized == other.startMinimized &&
          showTermsOnStart == other.showTermsOnStart &&
          themeColor == other.themeColor &&
          theme == other.theme &&
          autoStartOnBoot == other.autoStartOnBoot;

  @override
  int get hashCode => Object.hash(
        buddyName,
        buddyAvatar,
        destPath,
        showNotifications,
        startMinimized,
        showTermsOnStart,
        themeColor,
        theme,
        autoStartOnBoot,
      );

  @override
  String toString() => 'AppSettings{buddyName: $buddyName}';
}

// Default settings
AppSettings get defaultSettings => AppSettings(
      buddyName: SystemInfo.getSystemHostname(), // Use device name as default
      destPath: '', // Will be set to Downloads/Zipline by the app
    );