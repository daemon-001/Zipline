import 'dart:convert';

enum MessageType {
  invalid(0x00),
  helloBroadcast(0x01),
  helloUnicast(0x02),
  goodbye(0x03),
  helloPortBroadcast(0x04),
  helloPortUnicast(0x05),
  transferRequest(0x06),
  transferAccept(0x07),
  transferDecline(0x08);

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
  
  // Transfer request specific fields
  final String? transferId;
  final int? totalFiles;
  final int? totalSize;
  final String? transferDescription;
  final List<String>? fileNames;

  const BuddyMessage({
    required this.type,
    required this.port,
    required this.signature,
    this.adapterName,
    this.connectionType,
    this.transferId,
    this.totalFiles,
    this.totalSize,
    this.transferDescription,
    this.fileNames,
  });

  bool get isValid => type != MessageType.invalid;

  static BuddyMessage goodbye() => const BuddyMessage(
        type: MessageType.goodbye,
        port: 0,
        signature: '',
      );

  // Factory constructor for transfer request messages
  factory BuddyMessage.transferRequest({
    required String transferId,
    required String senderSignature,
    required int totalFiles,
    required int totalSize,
    required String transferDescription,
    List<String>? fileNames,
  }) {
    return BuddyMessage(
      type: MessageType.transferRequest,
      port: 0,
      signature: senderSignature,
      transferId: transferId,
      totalFiles: totalFiles,
      totalSize: totalSize,
      transferDescription: transferDescription,
      fileNames: fileNames,
    );
  }

  // Factory constructor for transfer accept messages
  factory BuddyMessage.transferAccept({
    required String transferId,
    required String receiverSignature,
    String? saveLocation,
  }) {
    return BuddyMessage(
      type: MessageType.transferAccept,
      port: 0,
      signature: receiverSignature,
      transferId: transferId,
      transferDescription: saveLocation,
    );
  }

  // Factory constructor for transfer decline messages
  factory BuddyMessage.transferDecline({
    required String transferId,
    required String receiverSignature,
    String? reason,
  }) {
    return BuddyMessage(
      type: MessageType.transferDecline,
      port: 0,
      signature: receiverSignature,
      transferId: transferId,
      transferDescription: reason,
    );
  }

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
      String? transferId;
      int? totalFiles;
      int? totalSize;
      String? transferDescription;
      List<String>? fileNames;

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
          // Format: [type][port_2bytes][signature_utf8] - Match protocol exactly
          if (data.length >= 3) {
            // Port is stored as native byte order
            port = data[1] | (data[2] << 8);
            if (data.length > 3) {
              // Simple signature without adapter info for compatibility
              signature = utf8.decode(data.skip(3).toList());
            }
          }
          break;
          
        case MessageType.transferRequest:
          // Format: [type][transfer_data_json_utf8]
          if (data.length > 1) {
            final jsonStr = utf8.decode(data.skip(1).toList());
            final transferData = json.decode(jsonStr);
            signature = transferData['signature'] ?? '';
            transferId = transferData['transferId'];
            totalFiles = transferData['totalFiles'];
            totalSize = transferData['totalSize'];
            transferDescription = transferData['description'];
            if (transferData['fileNames'] != null) {
              fileNames = List<String>.from(transferData['fileNames']);
            }
          }
          break;
          
        case MessageType.transferAccept:
        case MessageType.transferDecline:
          // Format: [type][response_data_json_utf8]
          if (data.length > 1) {
            final jsonStr = utf8.decode(data.skip(1).toList());
            final responseData = json.decode(jsonStr);
            signature = responseData['signature'] ?? '';
            transferId = responseData['transferId'];
            transferDescription = responseData['data']; // Save location or decline reason
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
        transferId: transferId,
        totalFiles: totalFiles,
        totalSize: totalSize,
        transferDescription: transferDescription,
        fileNames: fileNames,
      );
    } catch (e) {
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
        // Format: [type][port_2bytes][signature_utf8] - Match protocol exactly
        result.add(port & 0xFF);        // Low byte first
        result.add((port >> 8) & 0xFF); // High byte second
        if (signature.isNotEmpty) {
          result.addAll(utf8.encode(signature)); // Simple signature only
        }
        break;
        
      case MessageType.transferRequest:
        // Format: [type][transfer_data_json_utf8]
        final transferData = {
          'signature': signature,
          'transferId': transferId,
          'totalFiles': totalFiles,
          'totalSize': totalSize,
          'description': transferDescription,
          if (fileNames != null) 'fileNames': fileNames,
        };
        result.addAll(utf8.encode(json.encode(transferData)));
        break;
        
      case MessageType.transferAccept:
      case MessageType.transferDecline:
        // Format: [type][response_data_json_utf8]
        final responseData = {
          'signature': signature,
          'transferId': transferId,
          'data': transferDescription, // Save location or decline reason
        };
        result.addAll(utf8.encode(json.encode(responseData)));
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