import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/peer.dart';
import '../utils/system_info.dart';
import 'device_message.dart';
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
  static const Duration heartbeatInterval = Duration(seconds: 60); // Regular heartbeat to prevent flooding
  static const Duration initialDiscoveryInterval = Duration(seconds: 3); // Initial discovery interval
  static const Duration peerTimeout = Duration(minutes: 2); // Peers timeout after 2 minutes of inactivity
  
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _initialDiscoveryTimer;
  Timer? _networkWatchTimer;
  Timer? _peerCleanupTimer;

  // Store peers by composite key: "ip:port:connectionType" to support multiple paths
  final Map<String, Peer> _peers = {};
  
  final Map<String, int> _localAddressCount = {};
  final Set<String> _badAddresses = {};

  final StreamController<Peer> _peerFoundController = StreamController<Peer>.broadcast();
  final StreamController<Peer> _peerLostController = StreamController<Peer>.broadcast();
  
  final StreamController<Map<String, dynamic>> _transferRequestController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _transferResponseController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _transferCancelController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Peer> get onPeerFound => _peerFoundController.stream;
  Stream<Peer> get onPeerLost => _peerLostController.stream;
  
  Stream<Map<String, dynamic>> get onTransferRequest => _transferRequestController.stream;
  Stream<Map<String, dynamic>> get onTransferResponse => _transferResponseController.stream;
  Stream<Map<String, dynamic>> get onTransferCancel => _transferCancelController.stream;

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
    String? deviceName,
    String? platform,
  }) async {
    try {
      _listenPort = port;
      _localSignature = await _generateLocalSignature(deviceName, platform);

      // Update interface cache before starting
      await _updateInterfaceCache();

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
    _currentLocalAddresses.clear();
    _badAddresses.clear();
    
    notifyListeners();
  }
  
  DateTime? _lastBroadcastTime;
  
  Future<void> sayHello() async {
    if (_socket == null) return;
    
    // Rate limit broadcasts - minimum 1 second between broadcasts
    final now = DateTime.now();
    if (_lastBroadcastTime != null && 
        now.difference(_lastBroadcastTime!).inMilliseconds < 1000) {
      return;
    }
    _lastBroadcastTime = now;
    
    // Use proper message type based on whether we're using default port
    final message = DeviceMessage(
      type: _listenPort == defaultPort ? MessageType.helloBroadcast : MessageType.helloPortBroadcast,
      port: _listenPort,
      signature: _localSignature,
    );
    
    await _broadcastMessage(message);
  }

  // Smart refresh - trigger discovery without clearing existing peers
  Future<void> refreshNeighbors() async {
    // Prevent multiple simultaneous refreshes
    if (_isRefreshing) return;
    _isRefreshing = true;
    
    try {
      // Clear peers that haven't been seen recently (older than 30 seconds)
      final now = DateTime.now();
      final cutoffTime = now.subtract(Duration(seconds: 30));
      
      final keysToRemove = <String>[];
      for (final entry in _peers.entries) {
        if (entry.value.lastSeen.isBefore(cutoffTime)) {
          keysToRemove.add(entry.key);
        }
      }
      
      for (final key in keysToRemove) {
        _peers.remove(key);
      }
      
      // Update interface cache before discovery
      await _updateInterfaceCache();
      
      // Trigger a new discovery broadcast
      await sayHello();
      
      notifyListeners();
      
      // Wait a bit to prevent rapid refreshes
      await Future.delayed(Duration(seconds: 1));
    } finally {
      _isRefreshing = false;
    }
  }
  
  bool _isRefreshing = false;

  Future<void> refreshPeers() async {
    // Use the same smart refresh approach - don't clear peers immediately
    await refreshNeighbors();
  }

  void sayGoodbye() {
    if (_socket == null) return;
    
    final message = DeviceMessage(
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

    if (_badAddresses.contains(senderAddress)) {
      return;
    }

    if (_isLocalAddress(datagram.address)) {
      final count = (_localAddressCount[senderAddress] ?? 0) + 1;
      _localAddressCount[senderAddress] = count;
      
      if (count > 5) {
        _badAddresses.add(senderAddress);
      }
      return;
    }

    try {
      final message = DeviceMessage.deserialize(datagram.data);
      _processMessage(message, datagram.address);
    } catch (e) {
    }
  }

  final Set<String> _currentLocalAddresses = {};

  bool _isLocalAddress(InternetAddress address) {
    return _currentLocalAddresses.contains(address.address) || 
           address.isLoopback || 
           address.address == '0.0.0.0';
  }

  void _processMessage(DeviceMessage message, InternetAddress senderAddress) {
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
        // Remove all peers from this sender IP
        final peersToRemove = <String>[];
        for (final entry in _peers.entries) {
          if (entry.value.address == senderIp) {
            peersToRemove.add(entry.key);
          }
        }
        for (final key in peersToRemove) {
          final peer = _peers.remove(key);
          if (peer != null) {
            _peerLostController.add(peer);
          }
        }
        if (peersToRemove.isNotEmpty) {
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
        
      case MessageType.transferCancel:
        _handleTransferCancel(message, senderAddress);
        break;
        
      default:
        break;
    }
  }

  void _handleHelloMessage(DeviceMessage message, InternetAddress senderAddress, bool shouldReply) {
    final senderIp = senderAddress.address;
    
    final signature = message.signature;
    final parts = signature.split(' at ');
    final name = parts.isNotEmpty ? parts[0] : 'Unknown User';
    
    final port = (message.port == 0) ? defaultPort : message.port;
    
    if (port <= 0 || port > 65535) {
      return;
    }
    
    _createPeerAndReply(senderIp, name, port, signature, message, senderAddress, shouldReply);
  }

  Future<void> _createPeerAndReply(String senderIp, String name, int port, String signature, 
      DeviceMessage message, InternetAddress senderAddress, bool shouldReply) async {
    // Detect connection type based on IP address and local interface
    String connectionType = await NetworkUtility.detectConnectionTypeFromIP(senderIp);
    
    // Also check which of our local interfaces can reach this peer
    String? localInterface;
    for (final entry in _interfaceInfoCache.entries) {
      if (_isInSameNetwork(entry.key, senderIp)) {
        localInterface = entry.value.type;
        // If we have more specific info from our interface, use it
        if (localInterface != 'Network' && localInterface != 'Unknown') {
          connectionType = localInterface;
        }
        break;
      }
    }
    
    // Create unique ID for this network path
    final pathId = '$senderIp:$port:$connectionType';
    
    // Check if this peer already exists
    final existingPeer = _peers[pathId];
    final now = DateTime.now();
    
    // Only create/update if it's new or has been a while since last update
    if (existingPeer == null || 
        now.difference(existingPeer.lastSeen).inSeconds > 2) {
      
      final peer = Peer(
        id: pathId, // Unique ID for this specific network path
        name: name,
        address: senderIp,
        port: port,
        platform: 'Network',
        lastSeen: now,
        signature: signature,
        connectionType: connectionType,
        adapterName: connectionType,
        avatar: AvatarWebServer.instance.getAvatarUrl(senderIp, port), // Avatar URL
      );

      // Store peer by composite key - allows multiple paths to same device
      _peers[pathId] = peer;
      
      // Only emit deviceFound for new peers or significant updates
      if (existingPeer == null) {
        _peerFoundController.add(peer);
      }
      
      notifyListeners();
    } else {
      // Just update the timestamp for existing peer
      _peers[pathId] = existingPeer.copyWith(lastSeen: now);
    }

    // Reply with unicast if this was a broadcast - use proper message type
    if (shouldReply) {
      final replyMessage = DeviceMessage(
        type: _listenPort == defaultPort ? MessageType.helloUnicast : MessageType.helloPortUnicast,
        port: _listenPort,
        signature: _localSignature,
      );
      _sendUnicast(replyMessage, senderAddress, port);
    }
  }

  // Helper to check if two IPs are in the same network
  bool _isInSameNetwork(String ip1, String ip2) {
    try {
      final parts1 = ip1.split('.').map(int.parse).toList();
      final parts2 = ip2.split('.').map(int.parse).toList();
      if (parts1.length != 4 || parts2.length != 4) return false;
      
      // Check if in same /24 subnet (common case)
      return parts1[0] == parts2[0] && parts1[1] == parts2[1] && parts1[2] == parts2[2];
    } catch (e) {
      return false;
    }
  }

  // Helper function to check if interface should be used for broadcasting
  // Use ALL active interfaces (no type filtering)
  bool _shouldUseInterface(NetworkInterface interface) {
    final name = interface.name.toLowerCase();
    
    // Only skip clearly problematic interfaces that would cause issues
    if (name.contains('loopback') ||
        name.contains('teredo') ||
        name.contains('isatap') ||
        name.contains('6to4') ||
        name.contains('tunnel')) {
      return false;
    }
    
    // Check if interface has at least one valid IPv4 address
    bool hasValidAddress = false;
    for (final addr in interface.addresses) {
      if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
        hasValidAddress = true;
        break;
      }
    }
    
    // Use ALL other interfaces that have valid addresses - WiFi, Ethernet, virtual, hotspot, etc.
    return hasValidAddress;
  }

  // Improved broadcast message sending
  Future<void> _broadcastMessage(DeviceMessage message) async {
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
        if (!_shouldUseInterface(interface)) {
          continue;
        }
        
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
          
          
          // Get broadcast address for this interface
          final broadcast = _getBroadcastAddress(addr.address);
          if (broadcast != null) {
            // Send to all discovered ports
            for (final port in ports) {
              try {
                _socket!.send(data, broadcast, port);
              } catch (e) {
                // Network broadcast may fail on some interfaces
              }
            }
          } else {
            // If no broadcast address, try direct subnet scanning as fallback
            _performDirectSubnetScan(addr.address, ports, data);
          }
          
          // Also send to common broadcast addresses as fallback
          // This helps with networks that might block subnet-specific broadcasts
          try {
            // Try 255.255.255.255 (limited broadcast)
            final limitedBroadcast = InternetAddress('255.255.255.255');
            for (final port in ports) {
              try {
                _socket!.send(data, limitedBroadcast, port);
              } catch (e) {
                // Ignore - some systems don't allow this
              }
            }
          } catch (e) {
            // Ignore
          }
        }
      }
    } catch (e) {
    }
  }

  // Store network interface info for better broadcast handling
  final Map<String, NetworkInterfaceInfo> _interfaceInfoCache = {};

  // Update network interface cache
  Future<void> _updateInterfaceCache() async {
    try {
      final interfaces = await NetworkUtility.getNetworkInterfaces();
      _interfaceInfoCache.clear();
      for (final interface in interfaces) {
        _interfaceInfoCache[interface.address] = interface;
      }
    } catch (e) {
      // Silent failure, will use fallback
    }
  }

  // Get broadcast address for a specific IP
  InternetAddress? _getBroadcastAddress(String ipAddress) {
    try {
      // First check cache for exact subnet info
      final interfaceInfo = _interfaceInfoCache[ipAddress];
      if (interfaceInfo?.broadcastAddress != null) {
        return InternetAddress(interfaceInfo!.broadcastAddress!);
      }
      
      // Fallback to simple calculation based on IP range
      final parts = ipAddress.split('.').map(int.parse).toList();
      if (parts.length != 4) return null;
      
      String broadcastAddr;
      
      // Use the original simple logic that was working
      // Class A private: 10.0.0.0/8
      if (parts[0] == 10) {
        broadcastAddr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
      }
      // Class B private: 172.16.0.0/12
      else if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) {
        broadcastAddr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
      }
      // Class C private: 192.168.0.0/16
      else if (parts[0] == 192 && parts[1] == 168) {
        broadcastAddr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
      }
      // Link-local addresses: 169.254.0.0/16
      else if (parts[0] == 169 && parts[1] == 254) {
        broadcastAddr = '169.254.255.255';
      }
      // For other IP ranges, assume /24 subnet
      else {
        broadcastAddr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
      }
      
      return InternetAddress(broadcastAddr);
      
    } catch (e) {
      return null;
    }
  }

  void _sendUnicast(DeviceMessage message, InternetAddress address, int port) {
    if (_socket == null) return;
    
    try {
      final data = message.serialize();
      _socket!.send(data, address, port);
    } catch (e) {
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => sayHello());
  }

  // Initial rapid discovery for faster peer detection
  void _startInitialDiscovery() {
    int discoveryCount = 0;
    _initialDiscoveryTimer = Timer.periodic(initialDiscoveryInterval, (timer) {
      sayHello();
      discoveryCount++;
      // Stop rapid discovery after 5 broadcasts (15 seconds)
      if (discoveryCount >= 5) {
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
        // Update interface cache
        await _updateInterfaceCache();
        
        // Get current network interfaces
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: true,
        );
        
        final currentInterfaces = <String>{};
        for (final interface in interfaces) {
          if (_shouldUseInterface(interface)) {
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
      }
    });
  }

  // Direct subnet scan as fallback when broadcast fails
  void _performDirectSubnetScan(String localIP, Set<int> ports, List<int> messageData) {
    // DISABLED: Direct subnet scanning can cause network flooding
    // and may interfere with normal discovery
    return;
    
    /* Original implementation - kept for reference
    if (_socket == null) return;
    
    try {
      final parts = localIP.split('.').map(int.parse).toList();
      if (parts.length != 4) return;
      
      // Scan the local /24 subnet (most common for home/office networks)
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      
      // Limit scan to avoid flooding
      for (int i = 1; i <= 254; i++) {
        if (i == parts[3]) continue; // Skip self
        
        final targetIP = '$subnet.$i';
        final targetAddress = InternetAddress.tryParse(targetIP);
        
        if (targetAddress != null) {
          // Send unicast to each IP in the subnet
          for (final port in ports) {
            try {
              _socket!.send(messageData, targetAddress, port);
            } catch (e) {
              // Ignore send errors
            }
          }
        }
      }
    } catch (e) {
      // Silent failure
    }
    */
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

  Future<String> _generateLocalSignature(String? deviceName, String? platform) async {
    try {
      // Use exact method for generating signature
      if (deviceName != null && deviceName.isNotEmpty) {
        // If custom device name is provided, use it with system hostname and platform
        return '${SystemInfo.getUsername(deviceName)} at ${SystemInfo.getSystemHostname()} (${SystemInfo.getPlatformName()})';
      } else {
        // Use full system signature
        return SystemInfo.getSystemSignature();
      }
    } catch (e) {
      // Provide optimistic fallback signature
      final fallbackName = deviceName?.isNotEmpty == true ? deviceName! : 'User';
      final fallbackHost = 'Computer';
      final fallbackPlatform = platform?.isNotEmpty == true ? platform! : 'Windows';
      return '$fallbackName at $fallbackHost ($fallbackPlatform)';
    }
  }

  // Transfer request handling methods
  void _handleTransferRequest(DeviceMessage message, InternetAddress senderAddress) {
    // Find the peer that sent this request
    Peer? senderPeer;
    for (final peer in _peers.values) {
      if (peer.address == senderAddress.address) {
        senderPeer = peer;
        break;
      }
    }
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
  
  void _handleTransferResponse(DeviceMessage message, InternetAddress senderAddress) {
    // Find the peer that sent this response
    Peer? senderPeer;
    for (final peer in _peers.values) {
      if (peer.address == senderAddress.address) {
        senderPeer = peer;
        break;
      }
    }
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
  
  void _handleTransferCancel(DeviceMessage message, InternetAddress senderAddress) {
    // Find the peer that sent this cancel
    Peer? senderPeer;
    for (final peer in _peers.values) {
      if (peer.address == senderAddress.address) {
        senderPeer = peer;
        break;
      }
    }
    if (senderPeer == null) return;
    
    final cancelData = {
      'transferId': message.transferId,
      'senderPeer': senderPeer,
      'senderSignature': message.signature,
      'reason': message.transferDescription, // Cancel reason
      'timestamp': DateTime.now(),
    };
    
    _transferCancelController.add(cancelData);
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
    final message = DeviceMessage.transferRequest(
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
    final message = DeviceMessage.transferAccept(
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
    final message = DeviceMessage.transferDecline(
      transferId: transferId,
      receiverSignature: _localSignature,
      reason: reason,
    );
    
    final targetAddress = InternetAddress.tryParse(targetPeer.address);
    if (targetAddress != null) {
      _sendUnicast(message, targetAddress, targetPeer.port);
    }
  }
  
  void sendTransferCancel({
    required Peer targetPeer,
    required String transferId,
    String? reason,
  }) {
    final message = DeviceMessage.transferCancel(
      transferId: transferId,
      senderSignature: _localSignature,
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
    _transferCancelController.close();
    super.dispose();
  }
}