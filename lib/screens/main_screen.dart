import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/peer.dart';
import '../models/app_settings.dart';
import '../services/peer_discovery_service.dart';
import '../services/file_transfer_service.dart';
import '../services/progress_dialog_manager.dart';
import '../services/network_utility.dart';
import '../widgets/network_warning_dialog.dart';
import '../widgets/top_notification.dart';
import '../widgets/tab_bar_widget.dart';
import '../widgets/user_profile_bar.dart';
import 'buddies_page.dart';
import 'recent_page.dart';
import 'about_page.dart';
import 'settings_page.dart';
import 'ip_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentPageIndex = 0;
  bool _showSettings = false;
  bool _showIpPage = false;
  Peer? _localPeer;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    // Hide any active progress dialogs
    ProgressDialogManager.instance.hideProgress();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
    final fileTransfer = Provider.of<FileTransferService>(context, listen: false);

    try {
      // Initialize app state first
      appState.initializeSettings();
      
      // Wait for settings to be loaded
      while (appState.settings == null) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      final settings = appState.settings!;
      
      // Check port availability before starting services
      if (mounted) {
        final portCheck = await fileTransfer.checkPortAvailability(settings.port);
        
        if (!portCheck['available']) {
          final result = await NetworkWarningDialog.showPortConflictDialog(
            context: context,
            port: settings.port,
            conflictingApp: portCheck['conflictingApp'],
          );
          
          if (result == 'change_port') {
            // Navigate to settings to change port
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => SettingsPage(onBack: () => Navigator.of(context).pop())),
            );
            return;
          } else if (result != 'retry') {
            // User cancelled or chose not to continue
            return;
          }
          // If retry, continue with initialization
        }
      }
      
      // Check network interfaces and show info if multiple
      final networkInterfaces = await NetworkUtility.getNetworkInterfaces();
      if (mounted && networkInterfaces.length > 1) {
        final interfaceList = networkInterfaces
            .map((interface) => '${interface.type} (${interface.name}): ${interface.address}')
            .toList();
        
        await NetworkWarningDialog.showNetworkInterfaceDialog(
          context: context,
          interfaces: interfaceList,
        );
      }
      
      // Start peer discovery service
      final discoveryStarted = await peerDiscovery.start(
        port: settings.port,
        buddyName: settings.buddyName,
        platform: 'Windows',
      );

      if (!discoveryStarted) {
        throw Exception('Failed to start peer discovery');
      }
      
      // BUGFIX: Start network monitoring to detect interface changes
      _startNetworkMonitoring(peerDiscovery);

      // Update file transfer service with settings
      fileTransfer.updateSettings(settings);
      
      // Connect peer discovery to file transfer service
      fileTransfer.setPeerDiscovery(peerDiscovery);
      
      // Initialize file transfer service (clean up old history)
      fileTransfer.initialize();
      
      // Start file transfer server
      final transferStarted = await fileTransfer.startServer(port: settings.port);
      if (!transferStarted) {
        // Show error dialog if server failed to start after port check passed
        if (mounted) {
          await NetworkWarningDialog.showNetworkErrorDialog(
            context: context,
            error: 'Failed to start file transfer server on port ${settings.port}',
            suggestion: 'The port may have been taken by another application since the initial check. Try restarting the app or changing the port in settings.',
            canRetry: true,
          );
        }
        throw Exception('Failed to start file transfer server');
      }

      appState.setInitialized(true);

      // Create local peer for profile bar
      _createLocalPeer(settings);

      // Listen to transfer events
      fileTransfer.onSessionStarted.listen((session) {
        // Show popup progress dialog instead of switching pages
        if (mounted) {
          ProgressDialogManager.instance.showProgress(
            context, 
            session,
            onCancel: () {
              fileTransfer.cancelTransfer(session.id);
            },
          );
        }
      });

      fileTransfer.onSessionProgress.listen((session) {
        // Update progress dialog
        if (mounted) {
          ProgressDialogManager.instance.updateProgress(session);
        }
      });

      fileTransfer.onSessionCompleted.listen((session) {
        // Update progress dialog to show completion (don't auto-close)
        if (mounted) {
          ProgressDialogManager.instance.updateProgress(session);
        }
      });

      fileTransfer.onSessionFailed.listen((session) {
        // Update progress dialog to show failure (don't auto-close)
        if (mounted) {
          ProgressDialogManager.instance.updateProgress(session);
        }
      });

    } catch (e) {
      // Try to continue with basic initialization even if some services fail
      try {
        appState.setInitialized(true);
      } catch (e2) {
        appState.setError('Failed to initialize: ${e.toString()}');
      }
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentPageIndex = index;
      _showSettings = false;
      _showIpPage = false;
    });
  }

  void _showSettingsPage() {
    setState(() {
      _showSettings = true;
    });
  }

  void _showIpList() {
    setState(() {
      _showIpPage = true;
    });
  }

  void _onBackPressed() {
    setState(() {
      _showSettings = false;
      _showIpPage = false;
    });
  }

  Widget _buildCurrentPage() {
    if (_showSettings) {
      return SettingsPage(onBack: _onBackPressed);
    }
    
    if (_showIpPage) {
      return IpPage(onBack: _onBackPressed);
    }

    switch (_currentPageIndex) {
      case 0:
        return const BuddiesPage();
      case 1:
        return const RecentPage();
      case 2:
        return const AboutPage();
      default:
        return const BuddiesPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          if (!appState.isInitialized) {
            if (appState.errorMessage != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
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
                        'Initialization Error',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        appState.errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _initializeServices,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Initializing Zipline...',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }
          }

          return Column(
            children: [
              // User profile bar
              if (!_showSettings && !_showIpPage)
                UserProfileBar(
                  localPeer: _localPeer,
                  onSettingsPressed: _showSettingsPage,
                  onIpAddressesPressed: _showIpList,
                ),
              if (!_showSettings && !_showIpPage)
                ZiplineTabBar(
                  currentIndex: _currentPageIndex,
                  onTabChanged: _onTabChanged,
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.surface,
                        theme.colorScheme.surface.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  child: _buildCurrentPage(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // BUGFIX: Monitor network interfaces for changes
  void _startNetworkMonitoring(PeerDiscoveryService peerDiscovery) {
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // Check if network interfaces have changed
        final currentInterfaces = await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: true,
        );
        
        // Simple heuristic: if interface count changed significantly, refresh peers
        if (currentInterfaces.length != _lastInterfaceCount) {
          _lastInterfaceCount = currentInterfaces.length;
          // Refresh neighbors to discover new peers
          await peerDiscovery.refreshNeighbors();
        }
      } catch (e) {
        // Silently handle network monitoring errors
      }
    });
  }

  int _lastInterfaceCount = 0;

  void _createLocalPeer(AppSettings settings) {
    _localPeer = Peer(
      id: 'local',
      name: settings.buddyName,
      address: '127.0.0.1', // Will be updated with actual IP
      port: settings.port,
      platform: 'Windows',
      system: 'Local',
      lastSeen: DateTime.now(),
    );
  }
}