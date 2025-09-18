import 'dart:convert';

enum MessageType {
  invalid(0x00),
  helloBroadcast(0x01),
  helloUnicast(0x02),
  goodbye(0x03),
  helloPortBroadcast(0x04),
  helloPortUnicast(0x05);

  const MessageType(this.value);
  final int value;

  static MessageType fromValue(int value) {
    return MessageType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MessageType.invalid,
    );
  }

  static MessageType broadcastType(bool withPort) =>
      withPort ? MessageType.helloPortBroadcast : MessageType.helloBroadcast;

  static MessageType unicastType(bool withPort) =>
      withPort ? MessageType.helloPortUnicast : MessageType.helloUnicast;
}

class BuddyMessage {
  final MessageType type;
  final int port;
  final String signature;
  final String? adapterName;
  final String? connectionType;

  const BuddyMessage({
    required this.type,
    required this.port,
    required this.signature,
    this.adapterName,
    this.connectionType,
  });

  bool get isValid => type != MessageType.invalid;

  static BuddyMessage goodbye() => const BuddyMessage(
        type: MessageType.goodbye,
        port: 0,
        signature: '',
      );

  static BuddyMessage parse(List<int> data) {
    try {
      if (data.isEmpty) return const BuddyMessage(type: MessageType.invalid, port: 0, signature: '');

      // Message format: first byte is message type
      final typeValue = data[0];
      final type = MessageType.fromValue(typeValue);

      if (type == MessageType.invalid) {
        return const BuddyMessage(type: MessageType.invalid, port: 0, signature: '');
      }

      int port = 0;
      String signature = '';
      String? adapterName;
      String? connectionType;

      switch (type) {
        case MessageType.helloBroadcast:
        case MessageType.helloUnicast:
          // Format: [type][signature_utf8] or [type][signature_utf8][separator][adapter_info]
          if (data.length > 1) {
            final signatureData = utf8.decode(data.skip(1).toList());
            final parts = signatureData.split('|ADAPTER|');
            signature = parts[0];
            if (parts.length > 1) {
              final adapterParts = parts[1].split('|TYPE|');
              adapterName = adapterParts[0];
              if (adapterParts.length > 1) {
                connectionType = adapterParts[1];
              }
            }
          }
          break;
          
        case MessageType.goodbye:
          // Format: [type] or [type][signature_utf8] for identification
          if (data.length > 1) {
            signature = utf8.decode(data.skip(1).toList());
          }
          break;
          
        case MessageType.helloPortBroadcast:
        case MessageType.helloPortUnicast:
          // Format: [type][port_2bytes][signature_utf8] or with adapter info
          if (data.length >= 3) {
            // Port is stored as little-endian 16-bit integer
            port = data[1] | (data[2] << 8);
            if (data.length > 3) {
              final signatureData = utf8.decode(data.skip(3).toList());
              final parts = signatureData.split('|ADAPTER|');
              signature = parts[0];
              if (parts.length > 1) {
                final adapterParts = parts[1].split('|TYPE|');
                adapterName = adapterParts[0];
                if (adapterParts.length > 1) {
                  connectionType = adapterParts[1];
                }
              }
            }
          }
          break;
          
        default:
          return const BuddyMessage(type: MessageType.invalid, port: 0, signature: '');
      }

      return BuddyMessage(
        type: type,
        port: port,
        signature: signature,
        adapterName: adapterName,
        connectionType: connectionType,
      );
    } catch (e) {
      print('Error parsing BuddyMessage: $e');
      return const BuddyMessage(type: MessageType.invalid, port: 0, signature: '');
    }
  }

  // Alias for compatibility with optimized services
  static BuddyMessage deserialize(List<int> data) => parse(data);
  static BuddyMessage fromBytes(List<int> data) => parse(data);
  
  // Additional properties for compatibility
  String? get buddyName => signature.isNotEmpty ? signature : null;

  List<int> serialize() {
    final result = <int>[];
    
    // Add message type as single byte
    result.add(type.value);

    // Prepare signature with adapter info if available
    String fullSignature = signature;
    if (adapterName != null || connectionType != null) {
      fullSignature += '|ADAPTER|${adapterName ?? ''}';
      if (connectionType != null) {
        fullSignature += '|TYPE|$connectionType';
      }
    }

    switch (type) {
      case MessageType.helloBroadcast:
      case MessageType.helloUnicast:
        // Format: [type][signature_utf8_with_adapter_info]
        if (fullSignature.isNotEmpty) {
          result.addAll(utf8.encode(fullSignature));
        }
        break;
        
      case MessageType.goodbye:
        // Include signature for identification
        if (signature.isNotEmpty) {
          result.addAll(utf8.encode(signature));
        }
        break;
        
      case MessageType.helloPortBroadcast:
      case MessageType.helloPortUnicast:
        // Format: [type][port_2bytes_little_endian][signature_utf8_with_adapter_info]
        result.add(port & 0xFF);        // Low byte first (little-endian)
        result.add((port >> 8) & 0xFF); // High byte second
        if (fullSignature.isNotEmpty) {
          result.addAll(utf8.encode(fullSignature));
        }
        break;
        
      default:
        break;
    }

    return result;
  }

  // Alias for compatibility with optimized services
  List<int> toBytes() => serialize();

  @override
  String toString() => 'BuddyMessage{type: $type, port: $port, signature: $signature}';
}