import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

/// Network interface information
class NetworkInterfaceInfo {
  final String name;
  final String address;
  final String type; // WiFi, Ethernet, etc.
  final bool isActive;
  final String? subnetMask;
  final String? broadcastAddress;

  NetworkInterfaceInfo({
    required this.name,
    required this.address,
    required this.type,
    required this.isActive,
    this.subnetMask,
    this.broadcastAddress,
  });

  @override
  String toString() => '$type ($name): $address${subnetMask != null ? ' /$subnetMask' : ''}';
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
    }
    return null;
  }

  /// Get all active network interfaces
  /// Include ALL active interfaces (no restrictive filtering)
  static Future<List<NetworkInterfaceInfo>> getNetworkInterfaces() async {
    final interfaces = <NetworkInterfaceInfo>[];
    
    try {
      final networkInterfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // Get subnet mask information on Windows
      Map<String, Map<String, String>>? windowsNetworkInfo;
      if (Platform.isWindows) {
        windowsNetworkInfo = await _getWindowsNetworkInfo();
      }

      for (final interface in networkInterfaces) {
        // Skip only clearly problematic interfaces
        final name = interface.name.toLowerCase();
        if (name.contains('loopback') ||
            name.contains('teredo') ||
            name.contains('isatap') ||
            name.contains('6to4')) {
          continue;
        }
        
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            final interfaceType = _getInterfaceType(interface.name);
            
            // Get subnet mask and broadcast address
            String? subnetMask;
            String? broadcastAddress;
            
            if (windowsNetworkInfo != null && windowsNetworkInfo.containsKey(address.address)) {
              final info = windowsNetworkInfo[address.address];
              subnetMask = info?['mask'];
              broadcastAddress = calculateBroadcastAddress(address.address, subnetMask);
            } else {
              // Fallback to common subnet masks
              subnetMask = _guessSubnetMask(address.address);
              broadcastAddress = calculateBroadcastAddress(address.address, subnetMask);
            }
            
            interfaces.add(NetworkInterfaceInfo(
              name: interface.name,
              address: address.address,
              type: interfaceType,
              isActive: true,
              subnetMask: subnetMask,
              broadcastAddress: broadcastAddress,
            ));
          }
        }
      }
    } catch (e) {
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

  /// Determine interface type from name (improved detection)
  static String _getInterfaceType(String name) {
    final lowerName = name.toLowerCase();
    
    // Hotspot patterns (check first as they can be confused with WiFi)
    if (lowerName.contains('microsoft wi-fi direct virtual adapter') ||
        lowerName.contains('hosted network') ||
        lowerName.contains('mobile hotspot') ||
        lowerName.contains('wi-fi direct') ||
        lowerName.contains('soft ap') ||
        lowerName.contains('softap') ||
        lowerName.contains('hostednetwork')) {
      return 'Hotspot';
    }
    // WiFi patterns (check these first as they're more specific)
    else if (lowerName.contains('wi-fi') || 
        lowerName.contains('wifi') || 
        lowerName.contains('wireless') ||
        lowerName.contains('wlan') ||
        lowerName.contains('802.11') ||
        lowerName.contains('airport') ||
        lowerName.contains('wifi adapter') ||
        lowerName.contains('wireless network adapter') ||
        lowerName.contains('wireless lan')) {
      return 'WiFi';
    } 
    // Ethernet patterns
    else if (lowerName.contains('ethernet') || 
             lowerName.contains('eth') ||
             lowerName.contains('local area connection') ||
             (lowerName.contains('lan') && !lowerName.contains('wlan')) ||
             lowerName.contains('gigabit') ||
             lowerName.contains('fast ethernet') ||
             lowerName.contains('realtek pcie') ||
             lowerName.contains('intel ethernet') ||
             lowerName.contains('broadcom netxtreme') ||
             lowerName.contains('marvell yukon') ||
             lowerName.contains('killer e') ||
             lowerName.contains('network connection')) {
      return 'Ethernet';
    } 
    // Virtual interfaces (still identify them even though we use them)
    else if (lowerName.contains('vmware') || 
             lowerName.contains('virtualbox') ||
             lowerName.contains('hyper-v') ||
             lowerName.contains('vbox') ||
             lowerName.contains('virtual adapter') ||
             lowerName.contains('vethernet')) {
      return 'Virtual';
    }
    // Bluetooth
    else if (lowerName.contains('bluetooth') || 
             lowerName.contains('bt')) {
      return 'Bluetooth';
    } 
    // Mobile/USB connections
    else if (lowerName.contains('mobile') || 
             lowerName.contains('cellular') ||
             lowerName.contains('usb network') ||
             lowerName.contains('modem') ||
             lowerName.contains('ppp') ||
             lowerName.contains('dial') ||
             lowerName.contains('rndis')) {
      return 'Mobile';
    } 
    // Tunneling interfaces
    else if (lowerName.contains('tunnel') ||
             lowerName.contains('tap') ||
             lowerName.contains('tun') ||
             lowerName.contains('vpn')) {
      return 'Tunnel';
    }
    else {
      // For unknown interfaces, return 'Network' (neutral)
      return 'Network';
    }
  }

  /// Check connectivity to a specific IP and port
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

  /// Detect connection type (WiFi/Ethernet) based on IP address
  static Future<String> detectConnectionTypeFromIP(String ipAddress) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );

      // First, try to find the exact interface that has this IP
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && address.address == ipAddress) {
            final detectedType = _getInterfaceType(interface.name);
            return detectedType;
          }
        }
      }
      
      // If not found in local interfaces, check if it's in the same subnet as any local interface
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            if (_isInSameSubnet(ipAddress, address.address)) {
              final detectedType = _getInterfaceType(interface.name);
              return detectedType;
            }
          }
        }
      }
      
      // If still not found, use conservative fallback
      return _detectConnectionTypeByIPRange(ipAddress);
    } catch (e) {
      return 'Unknown';
    }
  }


  /// Check if two IP addresses are in the same subnet
  static bool _isInSameSubnet(String ip1, String ip2) {
    try {
      final parts1 = ip1.split('.').map(int.parse).toList();
      final parts2 = ip2.split('.').map(int.parse).toList();
      
      if (parts1.length != 4 || parts2.length != 4) return false;
      
      // Check if first 3 octets match (assuming /24 subnet)
      return parts1[0] == parts2[0] && parts1[1] == parts2[1] && parts1[2] == parts2[2];
    } catch (e) {
      return false;
    }
  }

  /// Detect connection type based on IP address range patterns
  static String _detectConnectionTypeByIPRange(String ipAddress) {
    try {
      final parts = ipAddress.split('.').map(int.parse).toList();
      if (parts.length != 4) return 'Unknown';
      
      // Only make very specific assumptions for known patterns
      if (parts[0] == 169 && parts[1] == 254) {
        // Link-local addresses (often used when no DHCP) - usually Ethernet
        return 'Ethernet';
      } else if (parts[0] == 10) {
        // Corporate networks often use 10.x.x.x
        return 'Network';
      } else if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) {
        // Private network range
        return 'Network';
      } else if (parts[0] == 192 && parts[1] == 168) {
        // Home networks - be conservative and just return Network
        // since both WiFi and Ethernet often use the same subnet
        return 'Network';
      }
      
      return 'Network';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Get Windows network information including subnet masks
  static Future<Map<String, Map<String, String>>?> _getWindowsNetworkInfo() async {
    if (!Platform.isWindows) return null;
    
    try {
      // Use PowerShell to get network adapter configuration
      final result = await Process.run('powershell', [
        '-Command',
        r'Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*"} | Select-Object IPAddress, PrefixLength | ConvertTo-Json'
      ]);
      
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        final Map<String, Map<String, String>> networkInfo = {};
        final jsonStr = result.stdout.toString().trim();
        
        try {
          dynamic decoded = jsonStr;
          if (jsonStr.startsWith('[') || jsonStr.startsWith('{')) {
            decoded = json.decode(jsonStr);
          }
          
          // Handle both single object and array responses
          final List<dynamic> addresses = decoded is List ? decoded : [decoded];
          
          for (final addr in addresses) {
            if (addr is Map) {
              final ip = addr['IPAddress']?.toString();
              final prefixLength = addr['PrefixLength'];
              
              if (ip != null && prefixLength != null) {
                final mask = _prefixLengthToSubnetMask(prefixLength);
                networkInfo[ip] = {'mask': mask};
              }
            }
          }
        } catch (e) {
          // Fallback to netsh if PowerShell fails
          return await _getWindowsNetworkInfoNetsh();
        }
        
        return networkInfo;
      }
    } catch (e) {
    }
    
    // Fallback to netsh
    return await _getWindowsNetworkInfoNetsh();
  }

  /// Fallback method using netsh
  static Future<Map<String, Map<String, String>>?> _getWindowsNetworkInfoNetsh() async {
    try {
      final result = await Process.run('netsh', ['interface', 'ip', 'show', 'addresses']);
      
      if (result.exitCode == 0) {
        final Map<String, Map<String, String>> networkInfo = {};
        final lines = result.stdout.toString().split('\n');
        
        String? currentIP;
        for (final line in lines) {
          if (line.contains('IP Address:')) {
            currentIP = line.split(':').last.trim();
          } else if (line.contains('Subnet Prefix:') && currentIP != null) {
            // Extract subnet mask from prefix notation (e.g., "192.168.1.0/24 (mask 255.255.255.0)")
            final match = RegExp(r'/(\d+)').firstMatch(line);
            if (match != null) {
              final prefixLength = int.parse(match.group(1)!);
              final mask = _prefixLengthToSubnetMask(prefixLength);
              networkInfo[currentIP] = {'mask': mask};
            }
          }
        }
        
        return networkInfo;
      }
    } catch (e) {
      // Silent failure
    }
    
    return null;
  }

  /// Convert CIDR prefix length to subnet mask
  static String _prefixLengthToSubnetMask(int prefixLength) {
    if (prefixLength < 0 || prefixLength > 32) {
      return '255.255.255.0'; // Default to /24
    }
    
    int mask = 0xffffffff << (32 - prefixLength);
    return '${(mask >> 24) & 0xff}.${(mask >> 16) & 0xff}.${(mask >> 8) & 0xff}.${mask & 0xff}';
  }

  /// Guess subnet mask based on IP address class
  static String _guessSubnetMask(String ipAddress) {
    try {
      final parts = ipAddress.split('.').map(int.parse).toList();
      if (parts.length != 4) return '255.255.255.0';
      
      // Class A
      if (parts[0] >= 1 && parts[0] <= 126) {
        // Private Class A (10.0.0.0/8) typically uses /24 in practice
        if (parts[0] == 10) {
          return '255.255.255.0';
        }
        return '255.0.0.0';
      }
      // Class B
      else if (parts[0] >= 128 && parts[0] <= 191) {
        // Private Class B (172.16.0.0/12) typically uses /24 in practice
        if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) {
          return '255.255.255.0';
        }
        return '255.255.0.0';
      }
      // Class C
      else if (parts[0] >= 192 && parts[0] <= 223) {
        return '255.255.255.0';
      }
      // Class D & E (multicast and reserved)
      else {
        return '255.255.255.0';
      }
    } catch (e) {
      return '255.255.255.0';
    }
  }

  /// Calculate broadcast address from IP and subnet mask
  static String? calculateBroadcastAddress(String ipAddress, String? subnetMask) {
    if (subnetMask == null) return null;
    
    try {
      final ipParts = ipAddress.split('.').map(int.parse).toList();
      final maskParts = subnetMask.split('.').map(int.parse).toList();
      
      if (ipParts.length != 4 || maskParts.length != 4) return null;
      
      final broadcastParts = <int>[];
      for (int i = 0; i < 4; i++) {
        // Network part stays the same, host part becomes all 1s
        broadcastParts.add(ipParts[i] | (~maskParts[i] & 0xff));
      }
      
      return broadcastParts.join('.');
    } catch (e) {
      return null;
    }
  }
}