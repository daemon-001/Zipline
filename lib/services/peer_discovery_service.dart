import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/peer.dart';
import 'buddy_message.dart';

class PeerDiscoveryService extends ChangeNotifier {
  static const int defaultPort = 7250;
  static const Duration heartbeatInterval = Duration(seconds: 5); // More frequent
  static const Duration peerTimeout = Duration(seconds: 30);

  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;

  final Map<String, Peer> _discoveredPeers = {}; // Key: "address:port:adapter"
  final Map<String, List<Peer>> _peersBySignature = {}; // Group peers by device signature
  final StreamController<Peer> _peerFoundController = StreamController<Peer>.broadcast();
  final StreamController<Peer> _peerLostController = StreamController<Peer>.broadcast();

  Stream<Peer> get onPeerFound => _peerFoundController.stream;
  Stream<Peer> get onPeerLost => _peerLostController.stream;

  // Get all peers as a flat list
  List<Peer> get discoveredPeers {
    // Flatten all peers from all connection profiles
    final allPeers = <Peer>[];
    for (final peerList in _peersBySignature.values) {
      allPeers.addAll(peerList);
    }
    return allPeers;
  }

  // Get all discovered peers grouped by device signature
  Map<String, List<Peer>> get peersBySignature => Map.from(_peersBySignature);
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

      // Create UDP socket for broadcasting and listening
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onDataReceived);

      // Start heartbeat timer
      _startHeartbeat();
      
      // Send initial discovery broadcasts more aggressively
      await _performInitialDiscovery();
      
      // Start cleanup timer
      _startCleanupTimer();

      // Send initial hello broadcast
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
    
    // Send goodbye message
    sayGoodbye();
    
    _socket?.close();
    _socket = null;
    
    _discoveredPeers.clear();
  }

  Future<void> sayHello() async {
    final message = BuddyMessage(
      type: MessageType.helloBroadcast,
      port: _listenPort,
      signature: _localSignature,
    );
    
    await _broadcastMessage(message);
  }

  Future<void> sayHelloTo(String address, int port) async {
    final message = BuddyMessage(
      type: MessageType.helloUnicast,
      port: _listenPort,
      signature: _localSignature,
    );
    
    _sendMessage(message, InternetAddress(address), port);
  }

  Future<void> sayGoodbye() async {
    final message = BuddyMessage.goodbye();
    await _broadcastMessage(message);
  }

  void _onDataReceived(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket!.receive();
    if (datagram == null) return;

    print('Received datagram from ${datagram.address.address}:${datagram.port}, ${datagram.data.length} bytes');

    final message = BuddyMessage.parse(datagram.data);
    if (!message.isValid) {
      print('Invalid message received from ${datagram.address.address}');
      return;
    }

    print('Valid message received - Type: ${message.type}, Signature: ${message.signature}');
    _processMessage(message, datagram.address);
  }

  void _processMessage(BuddyMessage message, InternetAddress senderAddress) {
    final senderKey = '${senderAddress.address}:${message.port}';
    
    switch (message.type) {
      case MessageType.helloBroadcast:
      case MessageType.helloPortBroadcast:
      case MessageType.helloUnicast:
      case MessageType.helloPortUnicast:
        _handleHelloMessage(message, senderAddress, senderKey);
        break;
        
      case MessageType.goodbye:
        _handleGoodbyeMessage(senderKey);
        break;
        
      case MessageType.invalid:
        break;
    }
  }

  void _handleHelloMessage(BuddyMessage message, InternetAddress senderAddress, String senderKey) {
    // Don't process our own messages
    if (message.signature == _localSignature) return;

    print('Processing hello message from $senderAddress: "${message.signature}"');

    // Parse signature in format: "Username at Hostname (Platform)"
    // Example: "Ravir at RAVI-PC (Windows)" or "Ravir at RAVI-PC"
    String name = 'Unknown';
    String hostname = '';
    String platform = 'Unknown';
    
    final signature = message.signature.trim();
    if (signature.isNotEmpty) {
      // Try to parse "Username at Hostname (Platform)" format
      final atIndex = signature.indexOf(' at ');
      if (atIndex != -1) {
        name = signature.substring(0, atIndex).trim();
        final remaining = signature.substring(atIndex + 4).trim();
        
        final platformIndex = remaining.lastIndexOf(' (');
        if (platformIndex != -1 && remaining.endsWith(')')) {
          hostname = remaining.substring(0, platformIndex).trim();
          platform = remaining.substring(platformIndex + 2, remaining.length - 1).trim();
        } else {
          hostname = remaining;
        }
      } else {
        // Fallback: treat entire signature as name
        name = signature;
      }
    }

    final displayName = hostname.isNotEmpty ? '$name at $hostname' : name;

    // Determine which adapter this message came through
    final adapterInfo = _getAdapterInfoForAddress(senderAddress.address);
    
    // Filter: Only include Ethernet and WiFi connections
    if (adapterInfo.connectionType != 'Ethernet' && adapterInfo.connectionType != 'WiFi') {
      print('Skipping peer on ${adapterInfo.connectionType} connection: ${senderAddress.address}');
      return; // Skip virtual, loopback, and other connection types
    }
    
    // For same device through same connection type, use IP as key to prevent duplicates
    final connectionKey = '${message.signature}:${adapterInfo.connectionType}';

    final peer = Peer(
      address: senderAddress.address,
      name: displayName,
      port: message.port > 0 ? message.port : 7250,
      platform: platform,
      adapterName: adapterInfo.adapterName,
      connectionType: adapterInfo.connectionType,
    );

    print('Processing hello message from ${senderAddress}: "${message.signature}"');

    // Update peer lists
    final existingPeer = _discoveredPeers[connectionKey];
    if (existingPeer == null) {
      _discoveredPeers[connectionKey] = peer;
      
      // Add to signature-based grouping
      if (_peersBySignature[message.signature] == null) {
        _peersBySignature[message.signature] = [];
      }
      _peersBySignature[message.signature]!.add(peer);
      
      _peerFoundController.add(peer);
      notifyListeners();
      print('Added new peer connection: ${peer.name} via ${peer.adapterName}');
      print('Connection key: $connectionKey');
      print('Total discovered peers: ${_discoveredPeers.length}');
    } else {
      _discoveredPeers[connectionKey] = peer;
      
      // Update in signature grouping
      final peerList = _peersBySignature[message.signature];
      if (peerList != null) {
        final index = peerList.indexWhere((p) => 
          p.address == peer.address && 
          p.port == peer.port && 
          p.adapterName == peer.adapterName
        );
        if (index != -1) {
          peerList[index] = peer;
        }
      }
      
      print('Updated existing peer connection: ${peer.name} via ${peer.adapterName}');
    }

    // Respond with unicast if this was a broadcast
    if (message.type == MessageType.helloBroadcast || 
        message.type == MessageType.helloPortBroadcast) {
      final responseMessage = BuddyMessage(
        type: MessageType.helloUnicast,
        port: _listenPort,
        signature: _localSignature,
      );
      _sendMessage(responseMessage, senderAddress, message.port);
    }
  }

  // Helper to determine which adapter a message came through
  ({String adapterName, String connectionType}) _getAdapterInfoForAddress(String ipAddress) {
    // Try to match the IP address to a known network interface
    try {
      // WiFi networks (typically 192.168.29.x in this setup)
      if (ipAddress.startsWith('192.168.29.')) {
        return (adapterName: 'WiFi', connectionType: 'WiFi');
      }
      // Link-local Ethernet addresses (169.254.x.x) - these are Ethernet connections
      else if (ipAddress.startsWith('169.254.')) {
        return (adapterName: 'Ethernet', connectionType: 'Ethernet');
      }
      // Standard private network ranges - likely Ethernet
      else if (ipAddress.startsWith('192.168.1.') || 
               ipAddress.startsWith('192.168.0.') ||
               ipAddress.startsWith('10.0.0.')) {
        return (adapterName: 'Ethernet', connectionType: 'Ethernet');
      }
      // Corporate networks
      else if (ipAddress.startsWith('172.')) {
        return (adapterName: 'Ethernet', connectionType: 'Ethernet');
      }
      // Skip virtual/loopback adapters
      else if (ipAddress.startsWith('192.168.56.') || // VirtualBox
               ipAddress.startsWith('192.168.99.') || // Docker
               ipAddress.startsWith('127.')) {         // Loopback
        return (adapterName: 'Virtual', connectionType: 'Virtual');
      }
      else {
        return (adapterName: 'Other', connectionType: 'Network');
      }
    } catch (e) {
      return (adapterName: 'Unknown', connectionType: 'Network');
    }
  }

  void _handleGoodbyeMessage(String senderKey) {
    final peer = _discoveredPeers.remove(senderKey);
    if (peer != null) {
      // Remove from signature grouping as well
      _peersBySignature.forEach((signature, peerList) {
        peerList.removeWhere((p) => 
          p.address == peer.address && 
          p.port == peer.port && 
          p.adapterName == peer.adapterName
        );
      });
      
      // Clean up empty signature groups
      _peersBySignature.removeWhere((signature, peerList) => peerList.isEmpty);
      
      _peerLostController.add(peer);
    }
  }

  Future<void> _performInitialDiscovery() async {
    // Send multiple discovery broadcasts with different message types and ports
    final ports = [_listenPort, 7250, 7251]; // Try multiple ports for better discovery
    
    // Check for PHYSICAL Ethernet connections only
    bool hasDirectEthernet = false;
    List<NetworkInterface> physicalEthernetInterfaces = [];
    
    // Helper function to check if an interface is likely virtual
    bool isVirtualInterface(NetworkInterface interface, InternetAddress address) {
      final name = interface.name.toLowerCase();
      final ip = address.address;
      
      // Common virtual adapter patterns - but EXCLUDE physical controller names
      if (name.contains('virtualbox') || 
          name.contains('vmware') || 
          name.contains('hyper-v') ||
          name.contains('docker') ||
          name.contains('vethernet')) {
        return true;
      }
      
      // Check for physical controller indicators (these are REAL adapters)
      if (name.contains('realtek') ||
          name.contains('intel') ||
          name.contains('broadcom') ||
          name.contains('marvell') ||
          name.contains('atheros') ||
          name.contains('nvidia') ||
          name.contains('family controller') ||
          name.contains('pcie') ||
          name.contains('gigabit')) {
        return false; // These are physical adapters
      }
      
      // Common virtual IP ranges - but be more selective
      if (ip.startsWith('192.168.56.') && name.contains('virtualbox')) { // VirtualBox Host-Only
        return true;
      }
      if (ip.startsWith('192.168.99.')) { // Docker Machine
        return true;
      }
      if (ip.startsWith('172.17.') && name.contains('docker')) { // Docker default
        return true;
      }
      if (ip.startsWith('10.0.75.') && name.contains('hyper')) { // Hyper-V
        return true;
      }
      
      return false; // Default to physical if unsure
    }
    
    try {
      final interfaces = await NetworkInterface.list(includeLinkLocal: true);
      
      // Find PHYSICAL Ethernet interfaces only
      physicalEthernetInterfaces = interfaces.where((i) => 
        i.name.toLowerCase().contains('ethernet') && 
        i.addresses.any((a) => 
          a.type == InternetAddressType.IPv4 && 
          !a.isLoopback && 
          !isVirtualInterface(i, a)
        )
      ).toList();
      
      hasDirectEthernet = physicalEthernetInterfaces.isNotEmpty;
      
      print('Found ${physicalEthernetInterfaces.length} PHYSICAL Ethernet interfaces: ${physicalEthernetInterfaces.map((i) => '${i.name}').join(', ')}');
      print('Physical Ethernet connection detected: $hasDirectEthernet');
    } catch (e) {
      print('Error checking for physical Ethernet: $e');
    }
    
    // More rounds for direct connections
    final rounds = hasDirectEthernet ? 5 : 3;
    
    for (int i = 0; i < rounds; i++) {
      for (final port in ports) {
        // Send both broadcast types
        final helloBroadcast = BuddyMessage(
          type: MessageType.helloBroadcast,
          port: _listenPort,
          signature: _localSignature,
        );
        
        final helloPortBroadcast = BuddyMessage(
          type: MessageType.helloPortBroadcast,
          port: _listenPort,
          signature: _localSignature,
        );
        
        await _broadcastMessageToPort(helloBroadcast, port);
        await _broadcastMessageToPort(helloPortBroadcast, port);
        
        // Additional targeted discovery for Ethernet
        if (hasDirectEthernet) {
          await _performDirectEthernetDiscovery();
        }
      }
      
      // Shorter delay for direct connections
      await Future.delayed(Duration(milliseconds: hasDirectEthernet ? 200 : 500));
    }
  }

  Future<void> _performDirectEthernetDiscovery() async {
    try {
      final interfaces = await NetworkInterface.list(includeLinkLocal: true);
      
      // Helper function to check if an interface is likely virtual
      bool isVirtualInterface(NetworkInterface interface, InternetAddress address) {
        final name = interface.name.toLowerCase();
        final ip = address.address;
        
        // Common virtual adapter patterns - but EXCLUDE physical controller names
        if (name.contains('virtualbox') || 
            name.contains('vmware') || 
            name.contains('hyper-v') ||
            name.contains('docker') ||
            name.contains('vethernet')) {
          return true;
        }
        
        // Check for physical controller indicators (these are REAL adapters)
        if (name.contains('realtek') ||
            name.contains('intel') ||
            name.contains('broadcom') ||
            name.contains('marvell') ||
            name.contains('atheros') ||
            name.contains('nvidia') ||
            name.contains('family controller') ||
            name.contains('pcie') ||
            name.contains('gigabit')) {
          return false; // These are physical adapters
        }
        
        // Common virtual IP ranges - but be more selective
        if (ip.startsWith('192.168.56.') && name.contains('virtualbox')) { // VirtualBox Host-Only
          return true;
        }
        if (ip.startsWith('192.168.99.')) { // Docker Machine
          return true;
        }
        if (ip.startsWith('172.17.') && name.contains('docker')) { // Docker default
          return true;
        }
        if (ip.startsWith('10.0.75.') && name.contains('hyper')) { // Hyper-V
          return true;
        }
        
        return false; // Default to physical if unsure
      }
      
      // Find PHYSICAL Ethernet interfaces only
      final physicalEthernetInterfaces = interfaces.where((i) => 
        i.name.toLowerCase().contains('ethernet') && 
        i.addresses.any((a) => 
          a.type == InternetAddressType.IPv4 && 
          !a.isLoopback && 
          !isVirtualInterface(i, a)
        )
      ).toList();
      
      print('Direct discovery on ${physicalEthernetInterfaces.length} PHYSICAL interfaces');
      
      for (final interface in physicalEthernetInterfaces) {
        print('Processing PHYSICAL Ethernet interface: ${interface.name}');
        
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.isLoopback && 
              !isVirtualInterface(interface, addr)) {
            print('  Direct discovery on ${interface.name}: ${addr.address}');
            
            // For direct connections, try scanning nearby IPs
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final baseIp = int.parse(parts[3]);
              final networkBase = '${parts[0]}.${parts[1]}.${parts[2]}';
              
              // Try common direct connection patterns
              final targetIps = <String>[];
              
              // Different strategies based on IP range
              if (addr.address.startsWith('169.254.')) {
                // Link-local: try a range of addresses (common for direct PC-to-PC)
                print('  Physical link-local detected, scanning range...');
                for (int i = 1; i <= 30; i++) {
                  if (i != baseIp) {
                    targetIps.add('$networkBase.$i');
                  }
                }
              } else if (addr.address.startsWith('192.168.')) {
                // Check if this is NOT a virtual range
                if (!addr.address.startsWith('192.168.56.')) { // Skip VirtualBox range
                  print('  Physical private network detected, scanning adjacent IPs...');
                  for (int offset = 1; offset <= 10; offset++) {
                    if (baseIp + offset <= 254) {
                      targetIps.add('$networkBase.${baseIp + offset}');
                    }
                    if (baseIp - offset >= 1) {
                      targetIps.add('$networkBase.${baseIp - offset}');
                    }
                  }
                  // Also try common router/gateway IPs
                  final commonIps = [1, 2, 10, 11, 100, 101, 254];
                  for (final ip in commonIps) {
                    if (ip != baseIp) {
                      targetIps.add('$networkBase.$ip');
                    }
                  }
                }
              } else {
                // Other networks: try adjacent addresses
                print('  Other physical network, scanning adjacent IPs...');
                for (int offset = 1; offset <= 5; offset++) {
                  if (baseIp + offset <= 254) {
                    targetIps.add('$networkBase.${baseIp + offset}');
                  }
                  if (baseIp - offset >= 1) {
                    targetIps.add('$networkBase.${baseIp - offset}');
                  }
                }
              }
              
              // Send targeted unicast hellos
              final helloUnicast = BuddyMessage(
                type: MessageType.helloUnicast,
                port: _listenPort,
                signature: _localSignature,
              );
              
              print('  Trying ${targetIps.length} target IPs for PHYSICAL ${interface.name}');
              for (final targetIp in targetIps) {
                try {
                  _sendMessage(helloUnicast, InternetAddress(targetIp), 7250);
                  _sendMessage(helloUnicast, InternetAddress(targetIp), 7251);
                } catch (e) {
                  // Continue with next address
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error in physical Ethernet discovery: $e');
    }
  }

  Future<void> _broadcastMessageToPort(BuddyMessage message, int port) async {
    final data = message.serialize();
    final broadcastAddresses = await _getBroadcastAddresses();
    
    print('Broadcasting ${message.type} to ${broadcastAddresses.length} addresses on port $port');
    
    for (final address in broadcastAddresses) {
      try {
        _socket?.send(data, address, port);
        print('Sent broadcast to $address:$port');
      } catch (e) {
        print('Failed to send broadcast to $address:$port: $e');
      }
    }
  }

  Future<void> _broadcastMessage(BuddyMessage message) async {
    final data = message.serialize();
    final broadcastAddresses = await _getBroadcastAddresses();
    
    for (final address in broadcastAddresses) {
      try {
        _socket?.send(data, address, _listenPort);
      } catch (e) {
        print('Failed to send broadcast to $address: $e');
      }
    }
  }

  void _sendMessage(BuddyMessage message, InternetAddress address, int port) {
    try {
      final data = message.serialize();
      _socket?.send(data, address, port);
    } catch (e) {
      print('Failed to send message to ${address.address}:$port: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      sayHello();
    });
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _cleanupExpiredPeers();
    });
  }

  void _cleanupExpiredPeers() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _discoveredPeers.entries) {
      if (now.difference(entry.value.lastSeen) > peerTimeout) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      final peer = _discoveredPeers.remove(key);
      if (peer != null) {
        // Remove from signature grouping as well
        _peersBySignature.forEach((signature, peerList) {
          peerList.removeWhere((p) => 
            p.address == peer.address && 
            p.port == peer.port && 
            p.adapterName == peer.adapterName
          );
        });
        
        _peerLostController.add(peer);
      }
    }
    
    // Clean up empty signature groups
    _peersBySignature.removeWhere((signature, peerList) => peerList.isEmpty);
    
    if (expiredKeys.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<List<InternetAddress>> _getBroadcastAddresses() async {
    final addresses = <InternetAddress>[];
    
    try {
      // Broadcast to ALL active IPv4 interfaces for maximum discovery
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: true,  // Essential for Ethernet connections without internet
        includeLoopback: false,
      );

      print('Checking ${interfaces.length} network interfaces for broadcasting...');
      
      for (final interface in interfaces) {
        print('Interface: ${interface.name}');
        
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            print('  IPv4: ${addr.address}');
            
            // Calculate broadcast address based on interface's subnet mask
            // For most Ethernet connections, this will be calculated correctly
            try {
              // Get network info for this interface address
              final ipParts = addr.address.split('.').map(int.parse).toList();
              if (ipParts.length == 4) {
                // For link-local addresses (169.254.x.x), use /16 subnet
                if (ipParts[0] == 169 && ipParts[1] == 254) {
                  final broadcast = InternetAddress('169.254.255.255');
                  addresses.add(broadcast);
                  print('    Added link-local broadcast: ${broadcast.address}');
                }
                // For private networks, calculate broadcast
                else if (ipParts[0] == 192 && ipParts[1] == 168) {
                  // Assume /24 for 192.168.x.x networks
                  final broadcast = InternetAddress('${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255');
                  addresses.add(broadcast);
                  print('    Added private network broadcast: ${broadcast.address}');
                }
                else if (ipParts[0] == 10) {
                  // For 10.x.x.x networks, try both /8 and /24
                  addresses.add(InternetAddress('10.255.255.255'));
                  addresses.add(InternetAddress('${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255'));
                  print('    Added 10.x.x.x broadcasts');
                }
                else if (ipParts[0] == 172 && ipParts[1] >= 16 && ipParts[1] <= 31) {
                  // For 172.16-31.x.x networks (/12)
                  addresses.add(InternetAddress('${ipParts[0]}.${ipParts[1]}.255.255'));
                  print('    Added 172.x.x.x broadcast');
                }
                else {
                  // For other networks, try standard broadcast
                  final broadcast = InternetAddress('${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255');
                  addresses.add(broadcast);
                  print('    Added standard broadcast: ${broadcast.address}');
                }
              }
            } catch (e) {
              print('    Error calculating broadcast for ${addr.address}: $e');
            }
          }
        }
      }

      // Always include common broadcast addresses
      final commonBroadcasts = [
        '255.255.255.255',  // Global broadcast
        '192.168.1.255',    // Common home network
        '192.168.0.255',    // Common router default
        '169.254.255.255',  // Link-local broadcast
        '10.0.0.255',       // Common corporate
      ];
      
      for (final broadcastAddr in commonBroadcasts) {
        final addr = InternetAddress(broadcastAddr);
        if (!addresses.contains(addr)) {
          addresses.add(addr);
        }
      }
      
      print('Broadcasting to ${addresses.length} addresses: ${addresses.map((a) => a.address).join(', ')}');
      
    } catch (e) {
      print('Error getting broadcast addresses: $e');
      // Fallback to common broadcast addresses
      addresses.addAll([
        InternetAddress('255.255.255.255'),
        InternetAddress('192.168.1.255'),
        InternetAddress('192.168.0.255'),
        InternetAddress('169.254.255.255'),
        InternetAddress('10.0.0.255'),
      ]);
    }
    
    return addresses;
  }

  Future<String> _generateLocalSignature([String? buddyName, String? platform]) async {
    final userName = Platform.environment['USERNAME'] ?? 
                     Platform.environment['USER'] ?? 
                     'User';
    final hostName = Platform.environment['COMPUTERNAME'] ?? 
                     Platform.environment['HOSTNAME'] ?? 
                     await _getDefaultBuddyName();
    final platformName = platform ?? _getPlatformName();
    
    // Format: "Username at Hostname (Platform)"
    return '$userName at $hostName ($platformName)';
  }

  Future<String> _getDefaultBuddyName() async {
    try {
      // Try to get computer name or default to 'User'
      final result = await Process.run('hostname', []);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      // Fall through to default
    }
    return 'User';
  }

  String _getPlatformName() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'Apple';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  void dispose() {
    stop();
    _peerFoundController.close();
    _peerLostController.close();
  }
}