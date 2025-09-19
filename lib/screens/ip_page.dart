import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../widgets/top_notification.dart';

class IpPage extends StatefulWidget {
  final VoidCallback onBack;

  const IpPage({super.key, required this.onBack});

  @override
  State<IpPage> createState() => _IpPageState();
}

class _IpPageState extends State<IpPage> {
  List<Map<String, String>> _networkInterfaces = [];
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

      setState(() {
        _networkInterfaces = interfaceData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _networkInterfaces = [{'error': 'Error loading network interfaces: ${e.toString()}', 'name': '', 'address': '', 'type': '', 'isLinkLocal': 'false'}];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // Header with modern styling
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: widget.onBack,
                      icon: Icon(Icons.arrow_back, color: theme.colorScheme.onPrimary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IP Addresses',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Klill',
                          ),
                        ),
                        Text(
                          'Your network connections',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontFamily: 'LiberationSans',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.router,
                      color: theme.colorScheme.onPrimary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState(theme)
                : _buildIpList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _loadNetworkInterfaces,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 6,
        tooltip: _isLoading ? 'Scanning...' : 'Refresh Network Interfaces',
        child: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                ),
              )
            : const Icon(Icons.refresh, size: 24),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.primary.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Scanning Network Interfaces',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
                fontFamily: 'Klill',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Discovering WiFi and Ethernet connections...',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIpList() {
    final theme = Theme.of(context);
    
    // Check for error case
    if (_networkInterfaces.isNotEmpty && _networkInterfaces.first.containsKey('error')) {
      return _buildErrorState(theme, _networkInterfaces.first['error']!);
    }
    
    if (_networkInterfaces.isEmpty) {
      return _buildEmptyState(theme);
    }

    return Column(
      children: [
        // Info banner with modern styling
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                theme.colorScheme.secondaryContainer.withValues(alpha: 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Network Addresses',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        fontFamily: 'Klill',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Other Zipline users can connect to you using any of these IP addresses.',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontFamily: 'LiberationSans',
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Network interfaces list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _networkInterfaces.length,
            itemBuilder: (context, index) {
              final interface = _networkInterfaces[index];
              return _buildNetworkInterfaceCard(interface, theme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.router_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Network Connections Found',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Klill',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Make sure you\'re connected to WiFi or Ethernet',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontFamily: 'LiberationSans',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tap the refresh button to scan again',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontFamily: 'LiberationSans',
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, String error) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Network Scan Failed',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Klill',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontFamily: 'LiberationSans',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tap the refresh button to try again',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontFamily: 'LiberationSans',
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkInterfaceCard(Map<String, String> interface, ThemeData theme) {
    final connectionType = interface['type']!;
    final ipAddress = interface['address']!;
    final interfaceName = interface['name']!;
    final isLinkLocal = interface['isLinkLocal'] == 'true';
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
            ],
          ),
        ),
        child: Row(
          children: [
            // Connection type icon with styling
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _getConnectionTypeColor(connectionType),
                    _getConnectionTypeColor(connectionType).withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _getConnectionTypeColor(connectionType).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  _getConnectionTypeIcon(connectionType),
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Interface info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ipAddress,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Klill',
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          interfaceName,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'LiberationSans',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isLinkLocal) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'LINK-LOCAL',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.error,
                              fontFamily: 'LiberationSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Copy button
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: () => _copyToClipboard(ipAddress),
                icon: Icon(
                  Icons.copy,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                tooltip: 'Copy IP address',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getConnectionTypeColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'ethernet':
        return const Color(0xFF4CAF50); // Modern green
      case 'wifi':
      case 'wireless':
        return const Color(0xFF2196F3); // Modern blue
      case 'vpn':
        return const Color(0xFFFF9800); // Modern orange
      case 'bluetooth':
        return const Color(0xFF9C27B0); // Modern purple
      case 'mobile':
        return const Color(0xFFE91E63); // Modern pink
      default:
        return const Color(0xFF9E9E9E); // Modern grey
    }
  }

  IconData _getConnectionTypeIcon(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'ethernet':
        return Icons.cable;
      case 'wifi':
      case 'wireless':
        return Icons.wifi;
      case 'vpn':
        return Icons.vpn_key;
      case 'bluetooth':
        return Icons.bluetooth;
      case 'mobile':
        return Icons.phone_android;
      default:
        return Icons.router;
    }
  }

  String _getConnectionTypeDisplayName(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'ethernet':
        return 'ETHERNET';
      case 'wifi':
      case 'wireless':
        return 'WiFi';
      case 'vpn':
        return 'VPN';
      case 'bluetooth':
        return 'BLUETOOTH';
      case 'mobile':
        return 'MOBILE';
      default:
        return connectionType.toUpperCase();
    }
  }

  void _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        TopNotification.show(
          context,
          title: 'IP Address Copied',
          message: text,
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        TopNotification.show(
          context,
          title: 'Copy Failed',
          message: 'Failed to copy to clipboard',
          type: NotificationType.error,
        );
      }
    }
  }
}