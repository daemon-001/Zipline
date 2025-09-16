import 'package:flutter/material.dart';
import '../models/peer.dart';

class BuddyListItem extends StatelessWidget {
  final Peer peer;
  final VoidCallback? onTap;
  final bool isLocalPeer;

  const BuddyListItem({
    super.key,
    required this.peer,
    this.onTap,
    this.isLocalPeer = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: isLocalPeer ? BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.blue.withOpacity(0.05),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ) : null,
          child: Row(
            children: [
              // Avatar/Platform icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.8),
                    ],
                  ),
                ),
                child: _buildAvatarContent(context),
              ),
              
              const SizedBox(width: 12),
              
              // Peer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            peer.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Klill',
                              color: isLocalPeer ? Colors.blue[700] : null,
                            ),
                          ),
                        ),
                        if (isLocalPeer)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[600],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'LiberationSans',
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${peer.address}:${peer.port}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontFamily: 'LiberationSans',
                          ),
                        ),
                        if (peer.connectionType != null && peer.connectionType!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getConnectionTypeColor(peer.connectionType!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              peer.connectionType!.toUpperCase(),
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
                    if (peer.adapterName != null && peer.adapterName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          peer.adapterName!,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                            fontFamily: 'LiberationSans',
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    if (peer.platform != null && peer.platform!.isNotEmpty)
                      Text(
                        peer.platform!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontFamily: 'LiberationSans',
                        ),
                      ),
                  ],
                ),
              ),
              
              // Platform logo
              if (peer.platform != null)
                Container(
                  width: 24,
                  height: 24,
                  child: _buildPlatformIcon(),
                ),
                
              const SizedBox(width: 8),
              
              // Arrow icon or local device icon
              if (isLocalPeer)
                Icon(
                  Icons.home,
                  size: 20,
                  color: Colors.blue[600],
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarContent(BuildContext context) {
    // Try to show first letter of name or generic icon
    if (peer.name.isNotEmpty) {
      return Center(
        child: Text(
          peer.name.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Klill',
          ),
        ),
      );
    } else {
      return const Center(
        child: Icon(
          Icons.computer,
          color: Colors.white,
          size: 24,
        ),
      );
    }
  }

  Widget _buildPlatformIcon() {
    IconData iconData;
    Color iconColor = Colors.grey[600]!;
    
    switch (peer.platform?.toLowerCase()) {
      case 'windows':
        iconData = Icons.desktop_windows;
        iconColor = Colors.blue[700]!;
        break;
      case 'apple':
      case 'macos':
        iconData = Icons.desktop_mac;
        iconColor = Colors.grey[700]!;
        break;
      case 'linux':
        iconData = Icons.computer;
        iconColor = Colors.orange[700]!;
        break;
      case 'android':
        iconData = Icons.smartphone;
        iconColor = Colors.green[700]!;
        break;
      case 'ios':
        iconData = Icons.phone_iphone;
        iconColor = Colors.grey[700]!;
        break;
      default:
        iconData = Icons.device_unknown;
        break;
    }
    
    return Icon(
      iconData,
      color: iconColor,
      size: 20,
    );
  }

  Color _getConnectionTypeColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'ethernet':
        return Colors.green[600]!;
      case 'wifi':
      case 'wireless':
        return Colors.blue[600]!;
      case 'vpn':
        return Colors.orange[600]!;
      case 'loopback':
        return Colors.grey[600]!;
      default:
        return Colors.purple[600]!;
    }
  }
}