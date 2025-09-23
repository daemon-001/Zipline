import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../services/profile_image_service.dart';

class UserProfileBar extends StatelessWidget {
  final Peer? localPeer;
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onIpAddressesPressed;

  const UserProfileBar({
    super.key,
    this.localPeer,
    this.onSettingsPressed,
    this.onIpAddressesPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar/Platform icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildProfileAvatar(context, theme),
            ),
            
            const SizedBox(width: 16),
            
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        localPeer != null ? _extractHostname(localPeer!.name) : 'Device',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Klill',
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.computer,
                                    size: 20,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // IP Addresses button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: onIpAddressesPressed,
                borderRadius: BorderRadius.circular(10),
                child: Icon(
                  Icons.router_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Settings button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: onSettingsPressed,
                borderRadius: BorderRadius.circular(10),
                child: Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildProfileAvatar(BuildContext context, ThemeData theme) {
    return FutureBuilder<Uint8List?>(
      future: ProfileImageService.instance.getProfileImage(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              snapshot.data!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          );
        } else {
          // Fallback to Zipline logo while loading
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/icon.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          );
        }
      },
    );
  }


  String _extractHostname(String displayName) {
    // Extract hostname from "username at hostname" format
    if (displayName.contains(' at ')) {
      final parts = displayName.split(' at ');
      if (parts.length >= 2) {
        return parts.last;
      }
    }
    // Remove device type in parentheses like "(Windows)", "(Linux)", etc.
    else if (displayName.contains(' (')) {
      return displayName.split(' (')[0];
    }
    return displayName;
  }
}
