import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../utils/system_info.dart';
import 'buddy_message.dart';

/// Peer discovery service for network device detection
/// Key features:
/// - Uses sender IP from UDP datagram for peer discovery (not self-reported)
/// - Broadcasts from all interfaces separately 
/// - Proper broadcast storm protection
/// - Identical message handling logic
class PeerDiscoveryService extends ChangeNotifier {
  static const int defaultPort = 6442;
  static const Duration heartbeatInterval = Duration(seconds: 5);
  static const Duration peerTimeout = Duration(seconds: 30);

  // Transfer: Single UDP socket bound to any interface
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;

  // Transfer: Simplified peer storage - key is IP address like original
  final Map<String, Peer> _peers = {};
  
  // Transfer: Broadcast storm protection exactly like messenger.cpp
  final Map<String, int> _localAddressCount = {};
  final Set<String> _badAddresses = {};

  final StreamController<Peer> _peerFoundController = StreamController<Peer>.broadcast();
  final StreamController<Peer> _peerLostController = StreamController<Peer>.broadcast();

  Stream<Peer> get onPeerFound => _peerFoundController.stream;
  Stream<Peer> get onPeerLost => _peerLostController.stream;

  List<Peer> get discoveredPeers => _peers.values.toList();

  // For UI compatibility - simplified grouping
  Map<String, List<Peer>> get peersBySignature {
    final Map<String, List<Peer>> grouped = {};
    for (final peer in _peers.values) {
      final signature = peer.signature ?? peer.name;
      grouped.putIfAbsent(signature, () => []).add(peer);
    }
    return grouped;
  }

  int? get listenPort => _listenPort;
  String _localSignature = '';
  int _listenPort = defaultPort;

  Future<bool> start({
    int port = defaultPort,
    String? buddyName,
    String? platform,
  }) async {
    try {
      _listenPort = port;
      _localSignature = await _generateLocalSignature(buddyName, platform);

      // Create UDP socket
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onDataReceived);

      print('Peer discovery started on port $port with signature: $_localSignature');

      // Start services
      _startHeartbeat();
      _startCleanupTimer();
      
      // Initial broadcast - simple and immediate
      await sayHello();
      
      return true;
    } catch (e) {
      print('Failed to start peer discovery: $e');
      return false;
    }
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    
    // Send goodbye
    sayGoodbye();
    
    _socket?.close();
    _socket = null;
    
    _peers.clear();
    _localAddressCount.clear();
    _currentLocalAddresses.clear(); // Transfer: Clear local address tracking
    _badAddresses.clear();
    
    notifyListeners();
  }

  Future<void> sayHello() async {
    if (_socket == null) return;
    
    final message = BuddyMessage(
      type: MessageType.helloBroadcast,
      port: _listenPort,
      signature: _localSignature,
    );
    
    await _broadcastMessage(message);
  }

  void sayGoodbye() {
    if (_socket == null) return;
    
    final message = BuddyMessage(
      type: MessageType.goodbye,
      port: _listenPort,
      signature: _localSignature,
    );
    
    _broadcastMessage(message);
  }

  void _onDataReceived(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;
    
    final datagram = _socket!.receive();
    if (datagram == null) return;

    final senderAddress = datagram.address.address;

    // Transfer: Broadcast storm protection - like badAddrs.contains(sender)
    if (_badAddresses.contains(senderAddress)) {
      return;
    }

    // Transfer: Check for local address (broadcast loop protection like localAddrs.contains)
    if (_isLocalAddress(datagram.address)) {
      final count = (_localAddressCount[senderAddress] ?? 0) + 1;
      _localAddressCount[senderAddress] = count;
      
      if (count > 5) {
        print('detected broadcast storm from $senderAddress');
        _badAddresses.add(senderAddress);
      }
      return;
    }

    try {
      final message = BuddyMessage.deserialize(datagram.data);
      _processMessage(message, datagram.address); // Transfer: Pass sender from datagram
    } catch (e) {
      // Transfer: Silently ignore invalid messages - no spam
    }
  }

  // Transfer: Track local addresses like localAddrs in messenger.cpp
  final Set<String> _currentLocalAddresses = {};

  bool _isLocalAddress(InternetAddress address) {
    // Transfer: Check if this is one of our local addresses (like localAddrs.contains(sender))
    return _currentLocalAddresses.contains(address.address) || 
           address.isLoopback || 
           address.address == '0.0.0.0';
  }

  void _processMessage(BuddyMessage message, InternetAddress senderAddress) {
    // Ignore our own messages
    if (message.signature == _localSignature) return;

    final senderIp = senderAddress.address;
    
    switch (message.type) {
      case MessageType.helloBroadcast:
      case MessageType.helloPortBroadcast:
        _handleHelloMessage(message, senderAddress, true);
        break;
        
      case MessageType.helloUnicast:
      case MessageType.helloPortUnicast:
        _handleHelloMessage(message, senderAddress, false);
        break;
        
      case MessageType.goodbye:
        final peer = _peers.remove(senderIp);
        if (peer != null) {
          _peerLostController.add(peer);
          notifyListeners();
        }
        break;
        
      default:
        break;
    }
  }

  void _handleHelloMessage(BuddyMessage message, InternetAddress senderAddress, bool shouldReply) {
    // Transfer: Use sender IP from UDP datagram as unique key (like QHash<QHostAddress, Peer>)
    final senderIp = senderAddress.address;
    
    // Transfer: Parse signature like original: "Username at Hostname (Platform)"
    final signature = message.signature ?? 'Unknown User';
    final parts = signature.split(' at ');
    final name = parts.isNotEmpty ? parts[0] : 'Unknown User';
    
    // Transfer: Use default port if message port is 0 (like protocolDefaultPort)
    final port = (message.port == 0) ? defaultPort : message.port;
    
    // Transfer: Validate port range
    if (port <= 0 || port > 65535) {
      print('Ignoring peer $senderIp with invalid port: $port');
      return;
    }
    
    // Transfer: Create peer using sender IP as unique identifier (like messenger.cpp)
    // Each IP address = separate peer entry (no grouping by signature)
    final peer = Peer(
      id: senderIp, // Transfer: Key by IP address like QHash<QHostAddress, Peer>
      name: name,
      address: senderIp, // Transfer: Always use sender IP from UDP datagram
      port: port,
      platform: 'Network',
      lastSeen: DateTime.now(),
      signature: signature,
      connectionType: 'Network',
      adapterName: 'Network',
    );

    // Transfer: Store peer by IP address (like peers[sender] = peer)
    final existingPeer = _peers[senderIp];
    if (existingPeer == null) {
      // New peer discovered
      _peers[senderIp] = peer;
      _peerFoundController.add(peer);
      print('📡 Transfer: New peer discovered - $name at $senderIp:$port');
    } else {
      // Update existing peer timestamp
      _peers[senderIp] = existingPeer.copyWith(lastSeen: DateTime.now());
    }

    // Transfer: Reply with unicast if this was a broadcast
    if (shouldReply) {
      final replyMessage = BuddyMessage(
        type: MessageType.helloUnicast,
        port: _listenPort,
        signature: _localSignature,
      );
      _sendUnicast(replyMessage, senderAddress, port);
    }

    notifyListeners();
  }

  // Transfer: Efficient broadcasting like messenger.cpp - broadcast from ALL interfaces
  Future<void> _broadcastMessage(BuddyMessage message) async {
    if (_socket == null) return;
    
    final data = message.serialize();
    
    // Transfer: Look for all the discovered ports (like original messenger.cpp)
    final ports = <int>{defaultPort};
    for (final peer in _peers.values) {
      if (!ports.contains(peer.port)) {
        ports.add(peer.port);
      }
    }

    // Transfer: recreate the local ip addresses list (like localAddrs.clear())
    _localAddressCount.clear();
    _currentLocalAddresses.clear();

    try {
      // Transfer: broadcast to all interfaces (like QNetworkInterface::allInterfaces())
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );

      for (final interface in interfaces) {
        // Transfer: Skip inactive interfaces
        if (interface.addresses.isEmpty) continue;
        
        for (final addr in interface.addresses) {
          // Transfer: IPv4 only, not loopback
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) continue;
          
          // Transfer: Skip bad addresses (broadcast storm protection)
          if (_badAddresses.contains(addr.address)) {
            print('skip bad addr ${addr.address} of ${interface.name}');
            continue;
          }
          
          // Transfer: Track local addresses (like localAddrs.insert(ipAddr, 0))
          _localAddressCount[addr.address] = 0;
          _currentLocalAddresses.add(addr.address);
          
          // Transfer: Calculate broadcast for this interface
          final broadcast = _calculateBroadcast(addr.address);
          if (broadcast != null) {
            // Transfer: Send to all discovered ports
            for (final port in ports) {
              try {
                _socket!.send(data, broadcast, port);
              } catch (e) {
                // Ignore broadcast failures on specific interfaces
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error during broadcast: $e');
    }
  }

  InternetAddress? _calculateBroadcast(String ipAddress) {
    try {
      final parts = ipAddress.split('.').map(int.parse).toList();
      if (parts.length != 4) return null;

      // Transfer: Simple broadcast calculation for common subnets
      if (parts[0] == 192 && parts[1] == 168) {
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      } else if (parts[0] == 10) {
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      } else if (parts[0] == 169 && parts[1] == 254) {
        // Transfer: Link-local broadcast
        return InternetAddress('169.254.255.255');
      } else {
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    } catch (e) {
      return null;
    }
  }

  void _sendUnicast(BuddyMessage message, InternetAddress address, int port) {
    if (_socket == null) return;
    
    try {
      final data = message.serialize();
      _socket!.send(data, address, port);
    } catch (e) {
      // Transfer: Ignore unicast send errors (like sendPacket)
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => sayHello());
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) => _cleanupExpiredPeers());
  }

  void _cleanupExpiredPeers() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    for (final entry in _peers.entries) {
      if (now.difference(entry.value.lastSeen) > peerTimeout) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      final peer = _peers.remove(key);
      if (peer != null) {
        _peerLostController.add(peer);
      }
    }

    if (expiredKeys.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<String> _generateLocalSignature(String? buddyName, String? platform) async {
    try {
      // Use exact method for generating signature
      if (buddyName != null && buddyName.isNotEmpty) {
        // If custom buddy name is provided, use it with system hostname and platform
        return '${SystemInfo.getUsername(buddyName)} at ${SystemInfo.getSystemHostname()} (${SystemInfo.getPlatformName()})';
      } else {
        // Use full system signature
        return SystemInfo.getSystemSignature();
      }
    } catch (e) {
      return 'User at Computer (Unknown)';
    }
  }

  void dispose() {
    stop();
    _peerFoundController.close();
    _peerLostController.close();
  }
}