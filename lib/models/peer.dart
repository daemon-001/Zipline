import 'package:json_annotation/json_annotation.dart';

// part 'peer.g.dart';

@JsonSerializable()
class Peer {
  final String id;
  final String address;
  final String name;
  final int port;
  final String? platform;
  final String? system;
  final String? avatar;
  final String? osLogo;
  final String? adapterName;
  final String? connectionType;
  final String? signature; // For protocol compatibility
  final DateTime lastSeen;

  Peer({
    required this.id,
    required this.address,
    required this.name,
    required this.port,
    this.platform,
    this.system,
    this.avatar,
    this.osLogo,
    this.adapterName,
    this.connectionType,
    this.signature,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  // factory Peer.fromJson(Map<String, dynamic> json) => _$PeerFromJson(json);
  // Map<String, dynamic> toJson() => _$PeerToJson(this);

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      id: json['id'] as String,
      address: json['address'] as String,
      name: json['name'] as String,
      port: json['port'] as int,
      platform: json['platform'] as String?,
      system: json['system'] as String?,
      avatar: json['avatar'] as String?,
      osLogo: json['osLogo'] as String?,
      adapterName: json['adapterName'] as String?,
      connectionType: json['connectionType'] as String?,
      signature: json['signature'] as String?,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'address': address,
      'name': name,
      'port': port,
      'platform': platform,
      'system': system,
      'avatar': avatar,
      'osLogo': osLogo,
      'adapterName': adapterName,
      'connectionType': connectionType,
      'signature': signature,
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  Peer copyWith({
    String? id,
    String? address,
    String? name,
    int? port,
    String? platform,
    String? system,
    String? avatar,
    String? osLogo,
    String? adapterName,
    String? connectionType,
    String? signature,
    DateTime? lastSeen,
  }) {
    return Peer(
      id: id ?? this.id,
      address: address ?? this.address,
      name: name ?? this.name,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      system: system ?? this.system,
      avatar: avatar ?? this.avatar,
      osLogo: osLogo ?? this.osLogo,
      adapterName: adapterName ?? this.adapterName,
      connectionType: connectionType ?? this.connectionType,
      signature: signature ?? this.signature,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  String get displayName => name.isNotEmpty ? name : address;

  String get platformLogo {
    final platformLower = platform?.toLowerCase() ?? '';
    switch (platformLower) {
      case 'windows':
        return '🪟';
      case 'linux':
        return '🐧';
      case 'apple':
      case 'macos':
      case 'ios':
        return '🍎';
      case 'android':
        return '🤖';
      default:
        return '💻';
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