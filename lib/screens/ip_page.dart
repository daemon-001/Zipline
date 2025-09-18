import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class IpPage extends StatefulWidget {
  final VoidCallback onBack;

  const IpPage({super.key, required this.onBack});

  @override
  State<IpPage> createState() => _IpPageState();
}

class _IpPageState extends State<IpPage> {
  List<String> _ipAddresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNetworkInterfaces();
  }

  Future<void> _loadNetworkInterfaces() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final addresses = <String>[];
      
      // Get all network interfaces with better filtering
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: true,  // Include link-local for better detection
        includeLoopback: false,
      );

      // Helper function to check if interface is virtual
      bool isVirtualInterface(NetworkInterface interface) {
        final name = interface.name.toLowerCase();
        return name.contains('virtualbox') || 
               name.contains('vmware') || 
               name.contains('hyper-v') ||
               name.contains('docker') ||
               name.contains('vethernet') ||
               name.contains('tun') ||
               name.contains('tap');
      }

      // Helper function to get connection type
      String getConnectionType(String interfaceName) {
        final name = interfaceName.toLowerCase();
        if (name.contains('wifi') || name.contains('wlan') || name.contains('wireless')) {
          return 'WiFi';
        } else if (name.contains('ethernet') || name.contains('eth') || name.contains('lan')) {
          return 'Ethernet';
        } else if (name.contains('bluetooth')) {
          return 'Bluetooth';
        } else if (name.contains('vpn') || name.contains('tun')) {
          return 'VPN';
        } else if (name.contains('mobile') || name.contains('cellular')) {
          return 'Mobile';
        } else {
          return 'Other';
        }
      }

       // Process interfaces and sort by priority - only WiFi and Ethernet
       final interfaceData = <Map<String, String>>[];
       
       for (final interface in interfaces) {
         if (isVirtualInterface(interface)) continue; // Skip virtual interfaces
         
         for (final addr in interface.addresses) {
           if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
             final connectionType = getConnectionType(interface.name);
             
             // Only include WiFi and Ethernet interfaces
             if (connectionType == 'WiFi' || connectionType == 'Ethernet') {
               interfaceData.add({
                 'name': interface.name,
                 'address': addr.address,
                 'type': connectionType,
                 'isLinkLocal': addr.address.startsWith('169.254.').toString(),
               });
             }
           }
         }
       }

      // Sort by priority: Ethernet first, then WiFi, then others
      interfaceData.sort((a, b) {
        final typeA = a['type']!;
        final typeB = b['type']!;
        
        if (typeA == 'Ethernet' && typeB != 'Ethernet') return -1;
        if (typeA != 'Ethernet' && typeB == 'Ethernet') return 1;
        if (typeA == 'WiFi' && typeB != 'WiFi') return -1;
        if (typeA != 'WiFi' && typeB == 'WiFi') return 1;
        
        return typeA.compareTo(typeB);
      });

      // Build address list with better formatting
      for (final data in interfaceData) {
        final name = data['name']!;
        final address = data['address']!;
        final type = data['type']!;
        final isLinkLocal = data['isLinkLocal'] == 'true';
        
        String displayName = name;
        if (type != 'Other') {
          displayName = '$type ($name)';
        }
        
        // Add indicator for link-local addresses
        if (isLinkLocal) {
          displayName += ' [Link-Local]';
        }
        
        addresses.add('$displayName: $address');
      }

      setState(() {
        _ipAddresses = addresses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _ipAddresses = ['Error loading network interfaces: ${e.toString()}'];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Text(
                    'IP Addresses',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Klill',
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading network interfaces...'),
                      ],
                    ),
                  )
                : _buildIpList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIpList() {
    if (_ipAddresses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.network_check,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
             Text(
               'No WiFi or Ethernet Interfaces Found',
               style: TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.bold,
               ),
             ),
             SizedBox(height: 8),
             Text(
               'Make sure you\'re connected via WiFi or Ethernet',
               style: TextStyle(
                 color: Colors.grey,
               ),
             ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: Colors.blue[50],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                     child: Text(
                       'These are your WiFi and Ethernet IP addresses. Other users can connect to you using any of these addresses.',
                       style: TextStyle(
                         color: Colors.blue,
                         fontSize: 14,
                       ),
                     ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _ipAddresses.length,
            itemBuilder: (context, index) {
              final ipInfo = _ipAddresses[index];
              final parts = ipInfo.split(': ');
              final interfaceName = parts.length > 1 ? parts[0] : 'Unknown';
              final ipAddress = parts.length > 1 ? parts[1] : ipInfo;
              
              // Extract connection type for styling
              final connectionType = _extractConnectionType(interfaceName);
              final isLinkLocal = interfaceName.contains('[Link-Local]');
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: _getInterfaceIcon(interfaceName),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ipAddress,
                          style: const TextStyle(
                            fontFamily: 'LiberationSans',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (connectionType != 'Other')
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getConnectionTypeColor(connectionType),
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        interfaceName.replaceAll(' [Link-Local]', ''),
                        style: TextStyle(
                          fontFamily: 'LiberationSans',
                          color: Colors.grey[600],
                        ),
                      ),
                      if (isLinkLocal)
                        Text(
                          'Link-Local Address (No DHCP)',
                          style: TextStyle(
                            fontFamily: 'LiberationSans',
                            fontSize: 11,
                            color: Colors.orange[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyToClipboard(ipAddress),
                    tooltip: 'Copy IP address',
                  ),
                ),
              );
            },
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loadNetworkInterfaces,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ),
        ),
      ],
    );
  }

  String _extractConnectionType(String interfaceName) {
    final name = interfaceName.toLowerCase();
    if (name.contains('wifi') || name.contains('wlan') || name.contains('wireless')) {
      return 'WiFi';
    } else if (name.contains('ethernet') || name.contains('eth') || name.contains('lan')) {
      return 'Ethernet';
    } else if (name.contains('bluetooth')) {
      return 'Bluetooth';
    } else if (name.contains('vpn') || name.contains('tun')) {
      return 'VPN';
    } else if (name.contains('mobile') || name.contains('cellular')) {
      return 'Mobile';
    } else {
      return 'Other';
    }
  }

  Color _getConnectionTypeColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'ethernet':
        return Colors.green[700]!;
      case 'wifi':
        return Colors.blue[700]!;
      case 'bluetooth':
        return Colors.indigo[700]!;
      case 'vpn':
        return Colors.orange[700]!;
      case 'mobile':
        return Colors.purple[700]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Widget _getInterfaceIcon(String interfaceName) {
    final name = interfaceName.toLowerCase();
    
    if (name.contains('wifi') || name.contains('wlan') || name.contains('wireless')) {
      return const Icon(Icons.wifi, color: Colors.blue);
    } else if (name.contains('ethernet') || name.contains('eth') || name.contains('lan')) {
      return const Icon(Icons.cable, color: Colors.green);
    } else if (name.contains('bluetooth')) {
      return const Icon(Icons.bluetooth, color: Colors.indigo);
    } else if (name.contains('vpn') || name.contains('tun')) {
      return const Icon(Icons.vpn_key, color: Colors.orange);
    } else if (name.contains('mobile') || name.contains('cellular')) {
      return const Icon(Icons.phone_android, color: Colors.purple);
    } else {
      return const Icon(Icons.network_check, color: Colors.grey);
    }
  }

  void _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied $text to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy to clipboard: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}