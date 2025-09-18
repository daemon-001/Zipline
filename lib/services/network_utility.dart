import 'dart:io';
import 'dart:async';

/// Network interface information
class NetworkInterfaceInfo {
  final String name;
  final String address;
  final String type; // WiFi, Ethernet, etc.
  final bool isActive;

  NetworkInterfaceInfo({
    required this.name,
    required this.address,
    required this.type,
    required this.isActive,
  });

  @override
  String toString() => '$type ($name): $address';
}

/// Utility class for network operations
class NetworkUtility {
  /// Check if a port is available for binding
  static Future<bool> isPortAvailable(int port) async {
    try {
      // Try to bind to the port
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } catch (e) {
      // Port is already in use or not accessible
      return false;
    }
  }

  /// Get the application name using the port (if available)
  static Future<String?> getPortUsage(int port) async {
    try {
      if (Platform.isWindows) {
        // Use netstat to find which process is using the port
        final result = await Process.run('netstat', ['-ano', '-p', 'TCP']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.contains(':$port ') && line.contains('LISTENING')) {
              // Extract PID from the line
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 5) {
                final pid = parts.last;
                // Get process name from PID
                final processResult = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
                if (processResult.exitCode == 0) {
                  final processLines = processResult.stdout.toString().split('\n');
                  if (processLines.isNotEmpty) {
                    final processInfo = processLines.first.split(',');
                    if (processInfo.isNotEmpty) {
                      return processInfo.first.replaceAll('"', '');
                    }
                  }
                }
              }
              break;
            }
          }
        }
      } else if (Platform.isLinux || Platform.isMacOS) {
        // Use lsof to find which process is using the port
        final result = await Process.run('lsof', ['-i', ':$port']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].trim().split(RegExp(r'\s+'));
            if (parts.isNotEmpty) {
              return parts.first;
            }
          }
        }
      }
    } catch (e) {
      print('Error checking port usage: $e');
    }
    return null;
  }

  /// Get all active network interfaces
  static Future<List<NetworkInterfaceInfo>> getNetworkInterfaces() async {
    final interfaces = <NetworkInterfaceInfo>[];
    
    try {
      final networkInterfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in networkInterfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            final interfaceType = _getInterfaceType(interface.name);
            interfaces.add(NetworkInterfaceInfo(
              name: interface.name,
              address: address.address,
              type: interfaceType,
              isActive: true,
            ));
          }
        }
      }
    } catch (e) {
      print('Error getting network interfaces: $e');
    }

    return interfaces;
  }

  /// Get the primary (preferred) network interface
  static Future<NetworkInterfaceInfo?> getPrimaryInterface() async {
    final interfaces = await getNetworkInterfaces();
    
    // Prefer Ethernet over WiFi, WiFi over others
    for (final interface in interfaces) {
      if (interface.type == 'Ethernet') {
        return interface;
      }
    }
    
    for (final interface in interfaces) {
      if (interface.type == 'WiFi') {
        return interface;
      }
    }
    
    return interfaces.isNotEmpty ? interfaces.first : null;
  }

  /// Determine interface type from name
  static String _getInterfaceType(String name) {
    final lowerName = name.toLowerCase();
    
    if (lowerName.contains('wi-fi') || 
        lowerName.contains('wifi') || 
        lowerName.contains('wireless') ||
        lowerName.contains('wlan')) {
      return 'WiFi';
    } else if (lowerName.contains('ethernet') || 
               lowerName.contains('eth') ||
               lowerName.contains('local area connection')) {
      return 'Ethernet';
    } else if (lowerName.contains('bluetooth') || 
               lowerName.contains('bt')) {
      return 'Bluetooth';
    } else if (lowerName.contains('vmware') || 
               lowerName.contains('virtualbox') ||
               lowerName.contains('hyper-v') ||
               lowerName.contains('vbox')) {
      return 'Virtual';
    } else if (lowerName.contains('mobile') || 
               lowerName.contains('cellular') ||
               lowerName.contains('usb')) {
      return 'Mobile';
    } else {
      return 'Unknown';
    }
  }

  /// Test connectivity to a specific IP and port
  static Future<bool> testConnectivity(String address, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(address, port, timeout: timeout);
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get local IP addresses for all interfaces
  static Future<List<String>> getLocalIPAddresses() async {
    final interfaces = await getNetworkInterfaces();
    return interfaces.map((interface) => interface.address).toList();
  }

  /// Get the best IP address for peer-to-peer communication
  static Future<String?> getBestIPAddress() async {
    final primary = await getPrimaryInterface();
    return primary?.address;
  }
}