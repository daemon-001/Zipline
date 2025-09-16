import 'package:json_annotation/json_annotation.dart';

// part 'peer.g.dart';

@JsonSerializable()
class Peer {
  final String address;
  final String name;
  final int port;
  final String? platform;
  final String? system;
  final String? avatar;
  final String? osLogo;
  final String? adapterName;
  final String? connectionType;
  final DateTime lastSeen;

  Peer({
    required this.address,
    required this.name,
    required this.port,
    this.platform,
    this.system,
    this.avatar,
    this.osLogo,
    this.adapterName,
    this.connectionType,
  }) : lastSeen = DateTime.now();

  // factory Peer.fromJson(Map<String, dynamic> json) => _$PeerFromJson(json);
  // Map<String, dynamic> toJson() => _$PeerToJson(this);

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      address: json['address'] as String,
      name: json['name'] as String,
      port: json['port'] as int,
      platform: json['platform'] as String?,
      system: json['system'] as String?,
      avatar: json['avatar'] as String?,
      osLogo: json['osLogo'] as String?,
      adapterName: json['adapterName'] as String?,
      connectionType: json['connectionType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'name': name,
      'port': port,
      'platform': platform,
      'system': system,
      'avatar': avatar,
      'osLogo': osLogo,
      'adapterName': adapterName,
      'connectionType': connectionType,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  Peer copyWith({
    String? address,
    String? name,
    int? port,
    String? platform,
    String? system,
    String? avatar,
    String? osLogo,
    String? adapterName,
    String? connectionType,
  }) {
    return Peer(
      address: address ?? this.address,
      name: name ?? this.name,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      system: system ?? this.system,
      avatar: avatar ?? this.avatar,
      osLogo: osLogo ?? this.osLogo,
      adapterName: adapterName ?? this.adapterName,
      connectionType: connectionType ?? this.connectionType,
    );
  }

  String get displayName => name.isNotEmpty ? name : address;

  String get platformLogo {
    final platformLower = platform?.toLowerCase() ?? '';
    switch (platformLower) {
      case 'windows':
        return 'assets/images/WindowsLogo.png';
      case 'linux':
        return 'assets/images/LinuxLogo.png';
      case 'apple':
      case 'macos':
      case 'ios':
        return 'assets/images/AppleLogo.png';
      case 'android':
        return 'assets/images/AndroidLogo.png';
      default:
        return 'assets/images/PcLogo.png';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer &&
          runtimeType == other.runtimeType &&
          address == other.address &&
          port == other.port &&
          adapterName == other.adapterName;

  @override
  int get hashCode => address.hashCode ^ port.hashCode ^ (adapterName?.hashCode ?? 0);

  @override
  String toString() => 'Peer{name: $name, address: $address, port: $port}';
}