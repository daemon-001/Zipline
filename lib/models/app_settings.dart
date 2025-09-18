import 'package:json_annotation/json_annotation.dart';

// part 'app_settings.g.dart';

@JsonSerializable()
class AppSettings {
  final String buddyName;
  final String buddyAvatar;
  final String destPath;
  final int port;
  final bool showNotifications;
  final bool startMinimized;
  final bool showTermsOnStart;
  final String themeColor;
  final bool autoStartOnBoot;

  const AppSettings({
    required this.buddyName,
    this.buddyAvatar = '',
    required this.destPath,
    this.port = 6442,
    this.showNotifications = true,
    this.startMinimized = false,
    this.showTermsOnStart = true,
    this.themeColor = '#3498db',
    this.autoStartOnBoot = false,
  });

  // Getter for compatibility with optimized services
  String get downloadDirectory => destPath;

  // factory AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);
  // Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      buddyName: json['buddyName'] as String,
      buddyAvatar: json['buddyAvatar'] as String? ?? '',
      destPath: json['destPath'] as String,
      port: json['port'] as int? ?? 6442,
      showNotifications: json['showNotifications'] as bool? ?? true,
      startMinimized: json['startMinimized'] as bool? ?? false,
      showTermsOnStart: json['showTermsOnStart'] as bool? ?? true,
      themeColor: json['themeColor'] as String? ?? '#3498db',
      autoStartOnBoot: json['autoStartOnBoot'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buddyName': buddyName,
      'buddyAvatar': buddyAvatar,
      'destPath': destPath,
      'port': port,
      'showNotifications': showNotifications,
      'startMinimized': startMinimized,
      'showTermsOnStart': showTermsOnStart,
      'themeColor': themeColor,
      'autoStartOnBoot': autoStartOnBoot,
    };
  }

  AppSettings copyWith({
    String? buddyName,
    String? buddyAvatar,
    String? destPath,
    int? port,
    bool? showNotifications,
    bool? startMinimized,
    bool? showTermsOnStart,
    String? themeColor,
    bool? autoStartOnBoot,
  }) {
    return AppSettings(
      buddyName: buddyName ?? this.buddyName,
      buddyAvatar: buddyAvatar ?? this.buddyAvatar,
      destPath: destPath ?? this.destPath,
      port: port ?? this.port,
      showNotifications: showNotifications ?? this.showNotifications,
      startMinimized: startMinimized ?? this.startMinimized,
      showTermsOnStart: showTermsOnStart ?? this.showTermsOnStart,
      themeColor: themeColor ?? this.themeColor,
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
          port == other.port &&
          showNotifications == other.showNotifications &&
          startMinimized == other.startMinimized &&
          showTermsOnStart == other.showTermsOnStart &&
          themeColor == other.themeColor &&
          autoStartOnBoot == other.autoStartOnBoot;

  @override
  int get hashCode => Object.hash(
        buddyName,
        buddyAvatar,
        destPath,
        port,
        showNotifications,
        startMinimized,
        showTermsOnStart,
        themeColor,
        autoStartOnBoot,
      );

  @override
  String toString() => 'AppSettings{buddyName: $buddyName, port: $port}';
}

// Default settings
AppSettings get defaultSettings => AppSettings(
      buddyName: 'User',
      destPath: '', // Will be set to Downloads/Zipline by the app
      port: 6442,
    );