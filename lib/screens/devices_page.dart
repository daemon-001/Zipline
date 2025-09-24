import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/peer_discovery_service.dart';
import '../models/peer.dart';
import '../widgets/device_list_item.dart';
import 'transfer_page.dart';

class DevicesPage extends StatefulWidget {
  final Function(Peer)? onPeerSelected;
  
  const DevicesPage({super.key, this.onPeerSelected});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _refreshPeers() async {
    // Prevent multiple refreshes
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
      await peerDiscovery.refreshNeighbors();
      
      // Add a small delay to show the refresh animation
      await Future.delayed(Duration(milliseconds: 500));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _onPeerSelected(Peer peer) {
    if (widget.onPeerSelected != null) {
      widget.onPeerSelected!(peer);
    } else {
      // Fallback to navigation if no callback provided
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TransferPage(
            peer: peer,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshPeers,
        child: Column(
          children: [
            if (_isRefreshing)
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Refreshing Devices...',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 14,
                        fontFamily: 'LiberationSans',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _buildDevicesList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isRefreshing ? null : _refreshPeers,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 6,
        tooltip: _isRefreshing ? 'Refreshing...' : 'Refresh Devices',
        child: _isRefreshing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              )
            : const Icon(Icons.refresh, size: 24),
      ),
    );
  }

  Widget _buildDevicesList() {
    return Consumer<PeerDiscoveryService>(
      builder: (context, peerDiscovery, child) {
        final peers = peerDiscovery.discoveredPeers;
        
        if (peers.isEmpty) {
          return _buildEmptyState();
        }
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: peers.length,
          itemBuilder: (context, index) {
            final peer = peers[index];
            
            return DeviceListItem(
              peer: peer,
              isLocalPeer: false,
              onTap: () => _onPeerSelected(peer),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.people_outline,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No devices found',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure that other device connected to the network',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
