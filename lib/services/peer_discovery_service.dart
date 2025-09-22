import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/peer.dart';
import '../utils/system_info.dart';
import 'buddy_message.dart';
import 'network_utility.dart';
import 'avatar_web_server.dart';

/// Peer discovery service for network device detection
/// Key features:
/// - Uses sender IP from UDP datagram for peer discovery (not self-reported)
/// - Broadcasts from all interfaces separately 
/// - Proper broadcast storm protection
/// - Identical message handling logic
/// - Smart peer timeout management for WiFi stability
class PeerDiscoveryService extends ChangeNotifier {
  static const int defaultPort = 6442; // Updated default port
  static const Duration heartbeatInterval = Duration(seconds: 30); // Faster heartbeat for better discovery
  static const Duration initialDiscoveryInterval = Duration(seconds: 2); // Quick initial discovery
  static const Duration peerTimeout = Duration(minutes: 3); // Peers timeout after 3 minutes of inactivity
  
  // Transfer: Single UDP socket bound to any interface
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _initialDiscoveryTimer;
  Timer? _networkWatchTimer;
  Timer? _peerCleanupTimer;

  // Transfer: Simplified peer storage - key is IP address like original
  final Map<String, Peer> _peers = {};
  
  // Transfer: Broadcast storm protection exactly like messenger.cpp
  final Map<String, int> _localAddressCount = {};
  final Set<String> _badAddresses = {};

  final StreamController<Peer> _peerFoundController = StreamController<Peer>.broadcast();
  final StreamController<Peer> _peerLostController = StreamController<Peer>.broadcast();
  
  // Transfer request stream controllers
  final StreamController<Map<String, dynamic>> _transferRequestController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _transferResponseController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Peer> get onPeerFound => _peerFoundController.stream;
  Stream<Peer> get onPeerLost => _peerLostController.stream;
  
  // Transfer request streams
  Stream<Map<String, dynamic>> get onTransferRequest => _transferRequestController.stream;
  Stream<Map<String, dynamic>> get onTransferResponse => _transferResponseController.stream;

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

      // Start avatar web server
      await AvatarWebServer.instance.start(port);

      // Create UDP socket
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onDataReceived);

      // Start services
      _startHeartbeat();
      _startInitialDiscovery();
      _startNetworkWatcher();
      _startPeerCleanup();
      
      // Initial broadcast - simple and immediate
      await sayHello();
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  void stop() {
    _heartbeatTimer?.cancel();
    _initialDiscoveryTimer?.cancel();
    _networkWatchTimer?.cancel();
    _peerCleanupTimer?.cancel();
    
    // Send goodbye
    sayGoodbye();
    
    // Stop avatar web server
    AvatarWebServer.instance.stop();
    
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
    
    // Use proper message type based on whether we're using default port
    final message = BuddyMessage(
      type: _listenPort == defaultPort ? MessageType.helloBroadcast : MessageType.helloPortBroadcast,
      port: _listenPort,
      signature: _localSignature,
    );
    
    await _broadcastMessage(message);
  }

  // Smart refresh - trigger discovery without clearing existing peers
  Future<void> refreshNeighbors() async {
    // Don't clear peers immediately - let discovery and timeout handle it
    // Just trigger a new discovery broadcast
    await sayHello();
    
    // Optionally mark all current peers as "old" for faster timeout
    final now = DateTime.now();
    final staleTime = now.subtract(Duration(minutes: 1)); // Mark as 1 minute old
    
    for (final peer in _peers.values) {
      // Update peer with earlier timestamp to encourage faster rediscovery
      _peers[peer.address] = peer.copyWith(lastSeen: staleTime);
    }
    
    notifyListeners();
  }

  // BUGFIX: Refresh peer information when network interfaces change
  Future<void> refreshPeers() async {
    // Use the same smart refresh approach - don't clear peers immediately
    await refreshNeighbors();
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
        // Instant peer removal on goodbye message
        final peer = _peers.remove(senderIp);
        if (peer != null) {
          _peerLostController.add(peer);
          notifyListeners();
        }
        break;
        
      case MessageType.transferRequest:
        _handleTransferRequest(message, senderAddress);
        break;
        
      case MessageType.transferAccept:
      case MessageType.transferDecline:
        _handleTransferResponse(message, senderAddress);
        break;
        
      default:
        break;
    }
  }

  void _handleHelloMessage(BuddyMessage message, InternetAddress senderAddress, bool shouldReply) {
    // Transfer: Use sender IP from UDP datagram as unique key (like QHash<QHostAddress, Peer>)
    final senderIp = senderAddress.address;
    
    // Transfer: Parse signature like original: "Username at Hostname (Platform)"
    final signature = message.signature;
    final parts = signature.split(' at ');
    final name = parts.isNotEmpty ? parts[0] : 'Unknown User';
    
    // Transfer: Use default port if message port is 0 (like protocolDefaultPort)
    final port = (message.port == 0) ? defaultPort : message.port;
    
    // Transfer: Validate port range
    if (port <= 0 || port > 65535) {
      return;
    }
    
    // Transfer: Immediate peer creation and response
    _createPeerAndReply(senderIp, name, port, signature, message, senderAddress, shouldReply);
  }

  Future<void> _createPeerAndReply(String senderIp, String name, int port, String signature, 
      BuddyMessage message, InternetAddress senderAddress, bool shouldReply) async {
    // Detect connection type based on IP address
    final connectionType = await NetworkUtility.detectConnectionTypeFromIP(senderIp);
    
    // Transfer: Create peer using sender IP as unique identifier (like messenger.cpp)
    // Each IP address = separate peer entry (no grouping by signature)
    final now = DateTime.now();
    final peer = Peer(
      id: senderIp, // Transfer: Key by IP address like QHash<QHostAddress, Peer>
      name: name,
      address: senderIp, // Transfer: Always use sender IP from UDP datagram
      port: port,
      platform: 'Network',
      lastSeen: now,
      signature: signature,
      connectionType: connectionType,
      adapterName: connectionType,
      avatar: AvatarWebServer.instance.getAvatarUrl(senderIp, port), // Avatar URL
    );

    // Store peer by IP address - always update timestamp for existing peers
    _peers[senderIp] = peer;
    
    // Emit buddyFound for EVERY hello message (even existing peers)
    _peerFoundController.add(peer);
    notifyListeners();

    // Reply with unicast if this was a broadcast - use proper message type
    if (shouldReply) {
      final replyMessage = BuddyMessage(
        type: _listenPort == defaultPort ? MessageType.helloUnicast : MessageType.helloPortUnicast,
        port: _listenPort,
        signature: _localSignature,
      );
      _sendUnicast(replyMessage, senderAddress, port);
    }
  }

  // Helper function to check if interface should be used for broadcasting
  // Use ALL active interfaces (no type filtering)
  bool _shouldUseInterface(NetworkInterface interface) {
    final name = interface.name.toLowerCase();
    
    // Only skip clearly problematic interfaces that would cause issues
    // This is much more permissive than the previous filtering
    if (name.contains('loopback') ||
        name.contains('teredo') ||
        name.contains('isatap') ||
        name.contains('6to4')) {
      return false;
    }
    
    // Use ALL other interfaces - WiFi, Ethernet, virtual, etc.
    // This matches behavior of not filtering by interface type
    return true;
  }

  // Improved broadcast message sending
  Future<void> _broadcastMessage(BuddyMessage message) async {
    if (_socket == null) return;
    
    final data = message.serialize();
    
    // Look for all the discovered ports (like original messenger.cpp)
    final ports = <int>{defaultPort};
    for (final peer in _peers.values) {
      if (!ports.contains(peer.port)) {
        ports.add(peer.port);
      }
    }

    // Recreate the local ip addresses list (like localAddrs.clear())
    _localAddressCount.clear();
    _currentLocalAddresses.clear();

    try {
      // Broadcast to ALL active interfaces
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );

      for (final interface in interfaces) {
        // Skip inactive interfaces
        if (interface.addresses.isEmpty) continue;
        
        // Only check if interface is up (no type filtering)
        if (!_shouldUseInterface(interface)) continue;
        
        for (final addr in interface.addresses) {
          // IPv4 only, not loopback
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) continue;
          
          // Skip bad addresses (broadcast storm protection)
          if (_badAddresses.contains(addr.address)) {
            continue;
          }
          
          // Track local addresses (like localAddrs.insert(ipAddr, 0))
          _localAddressCount[addr.address] = 0;
          _currentLocalAddresses.add(addr.address);
          
          // Calculate broadcast for this interface using better logic
          final broadcast = _calculateBroadcastAddress(addr.address);
          if (broadcast != null) {
            // Send to all discovered ports
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
      // Silently handle broadcast errors
    }
  }

  // Improved broadcast address calculation
  InternetAddress? _calculateBroadcastAddress(String ipAddress) {
    try {
      final parts = ipAddress.split('.').map(int.parse).toList();
      if (parts.length != 4) return null;

      // For most common network configurations, calculate broadcast address
      // This is more comprehensive than the previous simple approach
      
      // Class A private: 10.0.0.0/8
      if (parts[0] == 10) {
        // Typically use /24 subnets in 10.x.x.x networks
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
      
      // Class B private: 172.16.0.0/12
      if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) {
        // Typically use /24 subnets in 172.16-31.x.x networks
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
      
      // Class C private: 192.168.0.0/16
      if (parts[0] == 192 && parts[1] == 168) {
        // Standard /24 subnet
        return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
      
      // Link-local addresses: 169.254.0.0/16
      if (parts[0] == 169 && parts[1] == 254) {
        return InternetAddress('169.254.255.255');
      }
      
      // For other IP ranges, assume /24 subnet (most common)
      return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
      
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

  // Initial rapid discovery for faster peer detection
  void _startInitialDiscovery() {
    _initialDiscoveryTimer = Timer.periodic(initialDiscoveryInterval, (timer) {
      sayHello();
      // Stop rapid discovery after 30 seconds
      if (timer.tick >= 15) {
        timer.cancel();
        _initialDiscoveryTimer = null;
      }
    });
  }

  // Network watcher to detect interface changes and refresh peers
  // Monitor ALL active interfaces
  void _startNetworkWatcher() {
    Set<String> lastNetworkInterfaces = {};
    
    // Reduced frequency to avoid too frequent refreshes
    _networkWatchTimer = Timer.periodic(Duration(seconds: 60), (timer) async {
      try {
        // Get current network interfaces
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: true,
        );
        
        final currentInterfaces = <String>{};
        for (final interface in interfaces) {
          if (_shouldUseInterface(interface)) {  // Use new permissive filtering
            for (final addr in interface.addresses) {
              if (addr.type == InternetAddressType.IPv4) {
                currentInterfaces.add('${interface.name}:${addr.address}');
              }
            }
          }
        }
        
        // Check if network configuration changed significantly
        if (lastNetworkInterfaces.isNotEmpty && 
            !const SetEquality().equals(currentInterfaces, lastNetworkInterfaces)) {
          // Network changed - refresh peer discovery
          await refreshPeers();
        }
        
        lastNetworkInterfaces = currentInterfaces;
      } catch (e) {
        // Silently handle network checking errors
      }
    });
  }

  // Peer cleanup timer - remove inactive peers based on timeout
  void _startPeerCleanup() {
    _peerCleanupTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      final now = DateTime.now();
      final expiredPeers = <String>[];
      
      // Find peers that haven't been seen within the timeout period
      for (final entry in _peers.entries) {
        final peer = entry.value;
        final timeSinceLastSeen = now.difference(peer.lastSeen);
        
        if (timeSinceLastSeen > peerTimeout) {
          expiredPeers.add(entry.key);
        }
      }
      
      // Remove expired peers
      if (expiredPeers.isNotEmpty) {
        for (final expiredIp in expiredPeers) {
          final peer = _peers.remove(expiredIp);
          if (peer != null) {
            _peerLostController.add(peer);
          }
        }
        notifyListeners();
      }
    });
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
      // Provide optimistic fallback signature
      final fallbackName = buddyName?.isNotEmpty == true ? buddyName! : 'User';
      final fallbackHost = 'Computer';
      final fallbackPlatform = platform?.isNotEmpty == true ? platform! : 'Windows';
      return '$fallbackName at $fallbackHost ($fallbackPlatform)';
    }
  }

  // Transfer request handling methods
  void _handleTransferRequest(BuddyMessage message, InternetAddress senderAddress) {
    final senderPeer = _peers[senderAddress.address];
    if (senderPeer == null) return;
    
    final requestData = {
      'transferId': message.transferId,
      'senderPeer': senderPeer,
      'senderSignature': message.signature,
      'totalFiles': message.totalFiles,
      'totalSize': message.totalSize,
      'description': message.transferDescription,
      'fileNames': message.fileNames,
      'timestamp': DateTime.now(),
    };
    
    _transferRequestController.add(requestData);
  }
  
  void _handleTransferResponse(BuddyMessage message, InternetAddress senderAddress) {
    final senderPeer = _peers[senderAddress.address];
    if (senderPeer == null) return;
    
    final responseData = {
      'transferId': message.transferId,
      'responseType': message.type == MessageType.transferAccept ? 'accept' : 'decline',
      'senderPeer': senderPeer,
      'senderSignature': message.signature,
      'data': message.transferDescription, // Save location or decline reason
      'timestamp': DateTime.now(),
    };
    
    _transferResponseController.add(responseData);
  }
  
  // Public methods for sending transfer requests and responses
  void sendTransferRequest({
    required Peer targetPeer,
    required String transferId,
    required int totalFiles,
    required int totalSize,
    required String transferDescription,
    List<String>? fileNames,
  }) {
    final message = BuddyMessage.transferRequest(
      transferId: transferId,
      senderSignature: _localSignature,
      totalFiles: totalFiles,
      totalSize: totalSize,
      transferDescription: transferDescription,
      fileNames: fileNames,
    );
    
    final targetAddress = InternetAddress.tryParse(targetPeer.address);
    if (targetAddress != null) {
      _sendUnicast(message, targetAddress, targetPeer.port);
    }
  }
  
  void sendTransferAccept({
    required Peer targetPeer,
    required String transferId,
    String? saveLocation,
  }) {
    final message = BuddyMessage.transferAccept(
      transferId: transferId,
      receiverSignature: _localSignature,
      saveLocation: saveLocation,
    );
    
    final targetAddress = InternetAddress.tryParse(targetPeer.address);
    if (targetAddress != null) {
      _sendUnicast(message, targetAddress, targetPeer.port);
    }
  }
  
  void sendTransferDecline({
    required Peer targetPeer,
    required String transferId,
    String? reason,
  }) {
    final message = BuddyMessage.transferDecline(
      transferId: transferId,
      receiverSignature: _localSignature,
      reason: reason,
    );
    
    final targetAddress = InternetAddress.tryParse(targetPeer.address);
    if (targetAddress != null) {
      _sendUnicast(message, targetAddress, targetPeer.port);
    }
  }



  @override
  void dispose() {
    stop();
    _peerFoundController.close();
    _peerLostController.close();
    _transferRequestController.close();
    _transferResponseController.close();
    super.dispose();
  }
}