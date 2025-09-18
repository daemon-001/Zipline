import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../services/profile_image_service.dart';

class BuddyListItem extends StatelessWidget {
  final Peer peer;
  final VoidCallback? onTap;
  final bool isLocalPeer;
  final VoidCallback? onIpAddressesPressed;

  const BuddyListItem({
    super.key,
    required this.peer,
    this.onTap,
    this.isLocalPeer = false,
    this.onIpAddressesPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: isLocalPeer ? onIpAddressesPressed : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: isLocalPeer ? BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ) : null,
          child: Row(
            children: [
              // Avatar/Platform icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isLocalPeer 
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (isLocalPeer 
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondary).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildAvatarContent(context),
              ),
              
              const SizedBox(width: 16),
              
              // Peer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                isLocalPeer ? 'You - ${_extractHostname(peer.displayName)}' : _extractHostname(peer.displayName),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Klill',
                                  color: isLocalPeer 
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.computer,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isLocalPeer)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'You',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'LiberationSans',
                              ),
                            ),
                          ),
                      ],
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
                            'IP: ${peer.address}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'LiberationSans',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Port: ${peer.port}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'LiberationSans',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (peer.connectionType != null && peer.connectionType!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getConnectionTypeColor(peer.connectionType!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getConnectionTypeDisplayName(peer.connectionType!),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'LiberationSans',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Arrow icon for remote peers, IP icon for local peer
              if (!isLocalPeer)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.router_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarContent(BuildContext context) {
    final theme = Theme.of(context);
    
    // Use profile image processing method
    if (isLocalPeer) {
      return FutureBuilder<Uint8List?>(
        future: ProfileImageService.instance.getProfileImage(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  snapshot.data!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
            );
          } else {
            // Fallback to gradient with initial while loading
            return _buildFallbackAvatar(context, theme);
          }
        },
      );
    } else {
      // For remote peers, use avatar URL from peer
      if (peer.avatar != null && peer.avatar!.isNotEmpty) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.secondary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              peer.avatar!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to gradient if network image fails
                return _buildFallbackAvatar(context, theme);
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                // Show loading indicator
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        // Fallback to gradient with initial if no avatar URL
        return _buildFallbackAvatar(context, theme);
      }
    }
  }

  Widget _buildFallbackAvatar(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isLocalPeer 
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
            (isLocalPeer 
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          peer.name.isNotEmpty 
              ? peer.name.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Klill',
          ),
        ),
      ),
    );
  }


  String _extractHostname(String displayName) {
    // Extract hostname from formats like "Username at Hostname (Platform)" or "Hostname (Platform)"
    if (displayName.contains(' at ')) {
      // Format: "Username at Hostname (Platform)"
      final parts = displayName.split(' at ');
      if (parts.length > 1) {
        final hostnamePart = parts[1];
        // Remove platform info if present: "Hostname (Platform)" -> "Hostname"
        if (hostnamePart.contains(' (')) {
          return hostnamePart.split(' (')[0];
        }
        return hostnamePart;
      }
    } else if (displayName.contains(' (')) {
      // Format: "Hostname (Platform)"
      return displayName.split(' (')[0];
    }
    return displayName;
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
      case 'loopback':
        return 'LOOPBACK';
      case 'network':
        return 'NETWORK';
      default:
        return connectionType.toUpperCase();
    }
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
      case 'loopback':
        return const Color(0xFF9E9E9E); // Modern grey
      case 'network':
        return const Color(0xFF9C27B0); // Modern purple
      default:
        return const Color(0xFF9E9E9E); // Modern grey
    }
  }
}