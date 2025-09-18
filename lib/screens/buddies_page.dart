import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/peer_discovery_service.dart';
import '../models/peer.dart';
import '../widgets/buddy_list_item.dart';
import '../widgets/transfer_dialog.dart';

class BuddiesPage extends StatefulWidget {
  const BuddiesPage({super.key});

  @override
  State<BuddiesPage> createState() => _BuddiesPageState();
}

class _BuddiesPageState extends State<BuddiesPage> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _refreshPeers() async {
    setState(() {
      _isRefreshing = true;
    });
    
    final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
    await peerDiscovery.refreshNeighbors();
    
    setState(() {
      _isRefreshing = false;
    });
  }

  void _onPeerSelected(Peer peer) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => TransferDialog(peer: peer),
    );
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isRefreshing ? null : _refreshPeers,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 6,
        tooltip: _isRefreshing ? 'Refreshing...' : 'Refresh Buddies',
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

  Widget _buildBuddiesList() {
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
            
            return BuddyListItem(
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
                'No buddies found',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pull down to refresh or make sure other\nZipline users are on your network',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _refreshPeers,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh Buddies'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
