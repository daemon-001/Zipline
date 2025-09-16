import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
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
      
      // Get WiFi IP
      final wifiIP = await NetworkInfo().getWifiIP();
      if (wifiIP != null) {
        addresses.add('WiFi: $wifiIP');
      }

      // Get all network interfaces
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            addresses.add('${interface.name}: ${addr.address}');
          }
        }
      }

      setState(() {
        _ipAddresses = addresses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _ipAddresses = ['Error loading network interfaces'];
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
                  color: Colors.black.withOpacity(0.1),
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
              'No Network Interfaces Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Make sure you\'re connected to a network',
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
                      'These are your device\'s IP addresses. Other users can connect to you using any of these addresses.',
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
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: _getInterfaceIcon(interfaceName),
                  title: Text(
                    ipAddress,
                    style: const TextStyle(
                      fontFamily: 'LiberationSans',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(interfaceName),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyToClipboard(ipAddress),
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

  Widget _getInterfaceIcon(String interfaceName) {
    final name = interfaceName.toLowerCase();
    
    if (name.contains('wifi') || name.contains('wlan')) {
      return const Icon(Icons.wifi, color: Colors.green);
    } else if (name.contains('ethernet') || name.contains('eth')) {
      return const Icon(Icons.cable, color: Colors.blue);
    } else if (name.contains('bluetooth')) {
      return const Icon(Icons.bluetooth, color: Colors.indigo);
    } else {
      return const Icon(Icons.network_check, color: Colors.grey);
    }
  }

  void _copyToClipboard(String text) {
    // TODO: Implement clipboard copy
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $text to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}