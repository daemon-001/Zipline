import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../services/peer_discovery_service.dart';
import '../services/file_transfer_service.dart';
import '../models/peer.dart';
import '../widgets/buddy_list_item.dart';
import 'send_page.dart';

class BuddiesPage extends StatefulWidget {
  const BuddiesPage({super.key});

  @override
  State<BuddiesPage> createState() => _BuddiesPageState();
}

class _BuddiesPageState extends State<BuddiesPage> {
  List<Peer> _peers = [];
  bool _isRefreshing = false;
  Peer? _localPeer;
  List<NetworkInterface> _networkInterfaces = [];
  String _connectionInfo = '';

  @override
  void initState() {
    super.initState();
    _setupPeerDiscovery();
    _loadLocalInfo();
  }

  Future<void> _loadLocalInfo() async {
    try {
      // Get network interfaces - MUST include link-local for Ethernet detection!
      _networkInterfaces = await NetworkInterface.list(
        includeLinkLocal: true,  // Essential for detecting Ethernet connections
        includeLoopback: false,
      );
      
      // Get local peer information
      final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
      final userName = Platform.environment['USERNAME'] ?? 
                       Platform.environment['USER'] ?? 
                       'User';
      final hostName = Platform.environment['COMPUTERNAME'] ?? 
                       Platform.environment['HOSTNAME'] ?? 
                       'Computer';
      
      // Find primary network interface - prioritize PHYSICAL Ethernet adapters
      NetworkInterface? primaryInterface;
      String primaryAddress = '127.0.0.1';
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
      
      // Collect PHYSICAL Ethernet interfaces only
      for (final interface in _networkInterfaces) {
        if (!interface.name.toLowerCase().contains('loopback') && 
            interface.addresses.isNotEmpty &&
            interface.name.toLowerCase().contains('ethernet')) {
          
          // Check if this interface has any physical (non-virtual) addresses
          bool hasPhysicalAddress = false;
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && 
                !addr.isLoopback && 
                !isVirtualInterface(interface, addr)) {
              hasPhysicalAddress = true;
              break;
            }
          }
          
          if (hasPhysicalAddress) {
            physicalEthernetInterfaces.add(interface);
          }
        }
      }
      
      print('Found ${physicalEthernetInterfaces.length} PHYSICAL Ethernet interfaces: ${physicalEthernetInterfaces.map((i) => i.name).join(', ')}');
      
      // First pass: Look for physical Ethernet interfaces with regular IP addresses
      for (final interface in physicalEthernetInterfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.isLoopback && 
              !isVirtualInterface(interface, addr) &&
              !addr.address.startsWith('169.254.')) {
            primaryInterface = interface;
            primaryAddress = addr.address;
            print('Selected primary PHYSICAL Ethernet: ${interface.name} - ${addr.address}');
            break;
          }
        }
        if (primaryInterface != null) break;
      }
      
      // Second pass: If no regular physical Ethernet found, try link-local physical Ethernet
      if (primaryInterface == null) {
        for (final interface in physicalEthernetInterfaces) {
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && 
                !addr.isLoopback && 
                !isVirtualInterface(interface, addr) &&
                addr.address.startsWith('169.254.')) {
              primaryInterface = interface;
              primaryAddress = addr.address;
              print('Selected link-local PHYSICAL Ethernet: ${interface.name} - ${addr.address}');
              break;
            }
          }
          if (primaryInterface != null) break;
        }
      }
      
      // Third pass: If no physical Ethernet found, try WiFi or any other NON-VIRTUAL interface
      if (primaryInterface == null) {
        for (final interface in _networkInterfaces) {
          if (!interface.name.toLowerCase().contains('loopback') && 
              interface.addresses.isNotEmpty) {
            for (final addr in interface.addresses) {
              if (addr.type == InternetAddressType.IPv4 && 
                  !addr.isLoopback && 
                  !isVirtualInterface(interface, addr)) {
                primaryInterface = interface;
                primaryAddress = addr.address;
                print('Selected fallback NON-VIRTUAL interface: ${interface.name} - ${addr.address}');
                break;
              }
            }
            if (primaryInterface != null) break;
          }
        }
      }
      
      setState(() {
        _localPeer = Peer(
          id: '$primaryAddress:6442',
          address: primaryAddress,
          name: '$userName at $hostName',
          port: 6442,
          platform: 'Windows',
        );
        
        // Build connection info string
        final port = peerDiscovery.listenPort ?? 6442;
        final interfaceName = primaryInterface?.name ?? 'Unknown';
        
        // Count all active NON-VIRTUAL adapters
        final activeAdapters = _networkInterfaces.where((i) => 
          !i.name.toLowerCase().contains('loopback') && 
          i.addresses.isNotEmpty &&
          i.addresses.any((addr) => 
            addr.type == InternetAddressType.IPv4 && 
            !addr.isLoopback && 
            !isVirtualInterface(i, addr)
          )
        ).length;
        
        // Count specifically PHYSICAL Ethernet adapters
        final physicalEthernetCount = physicalEthernetInterfaces.length;
        
        if (physicalEthernetCount > 1) {
          _connectionInfo = 'Port: $port • $interfaceName • ${physicalEthernetCount} Physical Ethernet + ${activeAdapters - physicalEthernetCount} other adapters';
        } else if (physicalEthernetCount == 1) {
          _connectionInfo = 'Port: $port • $interfaceName (Physical) • $activeAdapters adapters active';
        } else {
          _connectionInfo = 'Port: $port • $interfaceName • $activeAdapters adapters active';
        }
      });
    } catch (e) {
      print('Error loading local info: $e');
    }
  }

  void _setupPeerDiscovery() {
    final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
    
    // Initial load
    setState(() {
      _peers = peerDiscovery.discoveredPeers;
    });

    // Listen to peer changes
    peerDiscovery.onPeerFound.listen((peer) {
      setState(() {
        _peers = peerDiscovery.discoveredPeers;
      });
    });

    peerDiscovery.onPeerLost.listen((peer) {
      setState(() {
        _peers = peerDiscovery.discoveredPeers;
      });
    });
  }

  Future<void> _refreshPeers() async {
    setState(() {
      _isRefreshing = true;
    });

    final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
    await peerDiscovery.sayHello();

    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _isRefreshing = false;
    });
  }

  void _onPeerSelected(Peer peer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SendPage(peer: peer),
      ),
    );
  }

  void _showNetworkDetails() {
    final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Network Connection Details',
          style: TextStyle(fontFamily: 'Klill'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Listen Port', '${peerDiscovery.listenPort ?? 6442}'),
              const SizedBox(height: 12),
              _buildDetailRow('Protocol', 'UDP/TCP'),
              const SizedBox(height: 12),
              _buildDetailRow('Discovery Mode', 'Broadcast + Unicast'),
              const SizedBox(height: 16),
              const Text(
                'Active Network Adapters:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Klill',
                ),
              ),
              const SizedBox(height: 8),
              ..._buildNetworkAdaptersList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
              fontFamily: 'LiberationSans',
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontFamily: 'LiberationSans'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildNetworkAdaptersList() {
    // Filter to show only enabled Ethernet and WiFi interfaces
    final activeInterfaces = _networkInterfaces.where((interface) {
      final name = interface.name.toLowerCase();
      
      // Only include Ethernet and WiFi interfaces
      final isEthernet = name.contains('ethernet');
      final isWiFi = name.contains('wifi') || name.contains('wireless');
      
      if (!(isEthernet || isWiFi)) {
        return false;
      }
      
      // Check if adapter has valid IPv4 addresses
      final ipv4Addresses = interface.addresses.where((addr) => 
        addr.type == InternetAddressType.IPv4 && !addr.isLoopback
      ).toList();
      
      if (ipv4Addresses.isEmpty) {
        return false;
      }
      
      // For WiFi: Only show if it has a proper network address (not just link-local)
      if (isWiFi) {
        return ipv4Addresses.any((addr) => !addr.address.startsWith('169.254.'));
      }
      
      // For Ethernet: Show if it has proper network address OR if it's being used for peer discovery
      final hasNonLinkLocal = ipv4Addresses.any((addr) => !addr.address.startsWith('169.254.'));
      if (hasNonLinkLocal) {
        return true;
      }
      
      // Check if this Ethernet adapter is being used for peer discovery
      // by seeing if we have any peers discovered through this interface
      final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
      final hasConnectedPeers = peerDiscovery.discoveredPeers.any((peer) {
        return peer.connectionType == 'Ethernet';
      });
      
      return hasConnectedPeers;
    }).toList();

    // Sort interfaces: Ethernet first, then WiFi, then others
    activeInterfaces.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      
      // Prioritize Ethernet interfaces
      if (aName.contains('ethernet') && !bName.contains('ethernet')) return -1;
      if (!aName.contains('ethernet') && bName.contains('ethernet')) return 1;
      
      // Then WiFi
      if (aName.contains('wifi') && !bName.contains('wifi')) return -1;
      if (!aName.contains('wifi') && bName.contains('wifi')) return 1;
      
      // Then alphabetical
      return aName.compareTo(bName);
    });

    print('Debug: Found ${activeInterfaces.length} enabled Ethernet/WiFi network interfaces:');
    for (final interface in activeInterfaces) {
      final ipv4s = interface.addresses
          .where((addr) => addr.type == InternetAddressType.IPv4)
          .map((addr) => addr.address)
          .join(', ');
      print('  ${interface.name}: $ipv4s');
    }

    if (activeInterfaces.isEmpty) {
      return [
        Text(
          'No Ethernet or WiFi adapters found',
          style: TextStyle(
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
            fontFamily: 'LiberationSans',
          ),
        ),
      ];
    }

    return activeInterfaces.map((interface) {
      final ipv4Addresses = interface.addresses
          .where((addr) => addr.type == InternetAddressType.IPv4 && !addr.isLoopback)
          .map((addr) => addr.address)
          .join(', ');
      
      final ipv6Addresses = interface.addresses
          .where((addr) => addr.type == InternetAddressType.IPv6)
          .map((addr) => addr.address)
          .join(', ');

      // Determine connection type
      String connectionType = _getConnectionType(interface.name);
      Color connectionColor = _getConnectionTypeColor(connectionType);

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    interface.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'LiberationSans',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: connectionColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    connectionType.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'LiberationSans',
                    ),
                  ),
                ),
              ],
            ),
            if (ipv4Addresses.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'IPv4: $ipv4Addresses',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
            if (ipv6Addresses.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'IPv6: ${ipv6Addresses.length > 50 ? '${ipv6Addresses.substring(0, 50)}...' : ipv6Addresses}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'LiberationSans',
                ),
              ),
            ],
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshPeers,
      child: Column(
        children: [
          // Connection info banner
          if (_connectionInfo.isNotEmpty)
            GestureDetector(
              onTap: _showNetworkDetails,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontFamily: 'LiberationSans',
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: Colors.blue[600]),
                  ],
                ),
              ),
            ),
          
          if (_isRefreshing)
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Refreshing Buddies...',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _buildBuddiesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBuddiesList() {
    final allPeers = <Peer>[];
    
    // Add local peer at the top if available
    if (_localPeer != null) {
      allPeers.add(_localPeer!);
    }
    
    // Add discovered peers
    allPeers.addAll(_peers);
    
    if (allPeers.isEmpty) {
      return _buildEmptyState();
    }
    
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: allPeers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final peer = allPeers[index];
        final isLocalPeer = index == 0 && _localPeer != null;
        
        return BuddyListItem(
          peer: peer,
          isLocalPeer: isLocalPeer,
          onTap: isLocalPeer ? null : () => _onPeerSelected(peer),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No buddies found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontFamily: 'Klill',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh or make sure other\nZipline users are on your network',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontFamily: 'LiberationSans',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshPeers,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  String _getConnectionType(String interfaceName) {
    final name = interfaceName.toLowerCase();
    if (name.contains('ethernet')) return 'Ethernet';
    if (name.contains('wifi') || name.contains('wireless')) return 'WiFi';
    if (name.contains('bluetooth')) return 'Bluetooth';
    if (name.contains('vpn') || name.contains('tun')) return 'VPN';
    if (name.contains('loopback')) return 'Loopback';
    return 'Other';
  }

  Color _getConnectionTypeColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'ethernet':
        return Colors.green[600]!;
      case 'wifi':
      case 'wireless':
        return Colors.blue[600]!;
      case 'bluetooth':
        return Colors.purple[600]!;
      case 'vpn':
        return Colors.orange[600]!;
      case 'loopback':
        return Colors.grey[600]!;
      default:
        return Colors.brown[600]!;
    }
  }
}