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

  const BuddyMessage({
    required this.type,
    required this.port,
    required this.signature,
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

      switch (type) {
        case MessageType.helloBroadcast:
        case MessageType.helloUnicast:
          // Format: [type][signature_utf8]
          if (data.length > 1) {
            signature = utf8.decode(data.skip(1).toList());
          }
          break;
          
        case MessageType.goodbye:
          // No additional data
          break;
          
        case MessageType.helloPortBroadcast:
        case MessageType.helloPortUnicast:
          // Format: [type][port_2bytes][signature_utf8]
          if (data.length >= 3) {
            // Port is stored as little-endian 16-bit integer
            port = data[1] | (data[2] << 8);
            if (data.length > 3) {
              signature = utf8.decode(data.skip(3).toList());
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
      );
    } catch (e) {
      print('Error parsing BuddyMessage: $e');
      return const BuddyMessage(type: MessageType.invalid, port: 0, signature: '');
    }
  }

  List<int> serialize() {
    final result = <int>[];
    
    // Add message type as single byte
    result.add(type.value);

    switch (type) {
      case MessageType.helloBroadcast:
      case MessageType.helloUnicast:
        // Format: [type][signature_utf8]
        if (signature.isNotEmpty) {
          result.addAll(utf8.encode(signature));
        }
        break;
        
      case MessageType.goodbye:
        // Only the type byte
        break;
        
      case MessageType.helloPortBroadcast:
      case MessageType.helloPortUnicast:
        // Format: [type][port_2bytes_little_endian][signature_utf8]
        result.add(port & 0xFF);        // Low byte first (little-endian)
        result.add((port >> 8) & 0xFF); // High byte second
        if (signature.isNotEmpty) {
          result.addAll(utf8.encode(signature));
        }
        break;
        
      default:
        break;
    }

    return result;
  }

  @override
  String toString() => 'BuddyMessage{type: $type, port: $port, signature: $signature}';
}