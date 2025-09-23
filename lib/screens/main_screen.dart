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
import '../services/save_location_service.dart';
import '../widgets/network_warning_dialog.dart';
import '../widgets/top_notification.dart';
import '../widgets/tab_bar_widget.dart';
import '../widgets/user_profile_bar.dart';
import '../widgets/transfer_request_dialog.dart';
import '../widgets/windows_action_bar.dart';
import 'buddies_page.dart';
import 'recent_page.dart';
import 'about_page.dart';
import 'settings_page.dart';
import 'ip_page.dart';
import 'transfer_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentPageIndex = 0;
  bool _showSettings = false;
  bool _showIpPage = false;
  bool _showTransferPage = false;
  Peer? _selectedPeer;
  Peer? _localPeer;
  final SaveLocationService _saveLocationService = SaveLocationService();

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _handleIncomingTransferRequest(Map<String, dynamic> requestData) async {
    final senderPeer = requestData['senderPeer'] as Peer;
    
    // Get the best save location for this peer
    await _saveLocationService.initialize();
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final defaultDownloadDir = appState.settings?.downloadDirectory ?? '';
    
    final currentSaveLocation = await _saveLocationService.getBestLocationForPeer(senderPeer.signature ?? senderPeer.name) ?? defaultDownloadDir;
    
    // Show the transfer request dialog
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TransferRequestDialog(
          requestData: requestData,
          currentSaveLocation: currentSaveLocation,
          onResponse: (accepted, saveLocation, remember, reason) async {
            Navigator.of(context).pop();
            
            final peerDiscovery = Provider.of<PeerDiscoveryService>(context, listen: false);
            final transferId = requestData['transferId'] as String;
            
            if (accepted && saveLocation != null) {
              // If user chose to remember this location, save it as default location
              if (remember) {
                await _saveLocationService.setDefaultLocation(saveLocation);
                
                // Also update the app settings with the new default location
                final appState = Provider.of<AppStateProvider>(context, listen: false);
                if (appState.settings != null) {
                  final settings = appState.settings!;
                  final updatedSettings = settings.copyWith(destPath: saveLocation);
                  appState.updateSettings(updatedSettings);
                }
              }
              
              // Register the incoming transfer with the file transfer service
              final fileTransferService = Provider.of<FileTransferService>(context, listen: false);
              fileTransferService.registerIncomingTransfer(
                transferId: transferId,
                senderAddress: senderPeer.address,
                customSaveLocation: saveLocation != currentSaveLocation ? saveLocation : null,
              );
              
              // Send acceptance
              peerDiscovery.sendTransferAccept(
                targetPeer: senderPeer,
                transferId: transferId,
                saveLocation: saveLocation,
              );
            } else {
              // Send decline
              peerDiscovery.sendTransferDecline(
                targetPeer: senderPeer,
                transferId: transferId,
                reason: reason ?? 'User declined the transfer',
              );
            }
          },
        ),
      );
    }
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
        bool portAvailable = false;
        while (!portAvailable) {
          final portCheck = await fileTransfer.checkPortAvailability(AppSettings.port);
          
          if (portCheck['available']) {
            portAvailable = true;
          } else {
            final result = await NetworkWarningDialog.showPortConflictDialog(
              context: context,
              port: AppSettings.port,
              conflictingApp: portCheck['conflictingApp'],
            );
            
            if (result == 'change_port') {
              // Port cannot be changed - show error message
              if (mounted) {
                await NetworkWarningDialog.showNetworkErrorDialog(
                  context: context,
                  error: 'Port ${AppSettings.port} is in use by another application',
                  suggestion: 'Please close the conflicting application and restart Zipline, or try again later.',
                  canRetry: true,
                );
              }
              return;
            } else if (result != 'retry') {
              // User cancelled or chose not to continue
              return;
            }
            // If retry, loop back to check port again
          }
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
        port: AppSettings.port,
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
      final transferStarted = await fileTransfer.startServer(port: AppSettings.port);
      if (!transferStarted) {
        // Show error dialog if server failed to start after port check passed
        if (mounted) {
          await NetworkWarningDialog.showNetworkErrorDialog(
            context: context,
            error: 'Failed to start file transfer server on port ${AppSettings.port}',
            suggestion: 'The port may have been taken by another application since the initial check. Try restarting the app.',
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

      // Listen for incoming transfer requests
      peerDiscovery.onTransferRequest.listen((requestData) {
        if (mounted) {
          _handleIncomingTransferRequest(requestData);
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
      _showTransferPage = false;
      _selectedPeer = null;
    });
  }

  void showTransferPage(Peer peer) {
    setState(() {
      _showTransferPage = true;
      _selectedPeer = peer;
    });
  }

  Widget _buildCurrentPage() {
    if (_showSettings) {
      return SettingsPage(onBack: _onBackPressed);
    }
    
    if (_showIpPage) {
      return IpPage(onBack: _onBackPressed);
    }

    if (_showTransferPage && _selectedPeer != null) {
      return TransferPage(
        peer: _selectedPeer!,
        onBack: _onBackPressed,
      );
    }

    switch (_currentPageIndex) {
      case 0:
        return BuddiesPage(onPeerSelected: showTransferPage);
      case 1:
        return const RecentPage();
      case 2:
        return const AboutPage();
      default:
        return BuddiesPage(onPeerSelected: showTransferPage);
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
              // Custom Windows action bar
              WindowsActionBar(
                title: 'Zipline',
              ),
              // User profile bar
              if (!_showSettings && !_showIpPage && !_showTransferPage)
                UserProfileBar(
                  localPeer: _localPeer,
                  onSettingsPressed: _showSettingsPage,
                  onIpAddressesPressed: _showIpList,
                ),
              if (!_showSettings && !_showIpPage && !_showTransferPage)
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
  // Reduced frequency since PeerDiscoveryService now has its own network watcher
  void _startNetworkMonitoring(PeerDiscoveryService peerDiscovery) {
    Timer.periodic(const Duration(minutes: 2), (timer) async {
      try {
        // Check if network interfaces have changed
        final currentInterfaces = await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: true,
        );
        
        // Only trigger refresh on significant changes (more than 1 interface difference)
        final interfaceCountDiff = (currentInterfaces.length - _lastInterfaceCount).abs();
        if (_lastInterfaceCount > 0 && interfaceCountDiff > 1) {
          _lastInterfaceCount = currentInterfaces.length;
          // Use smart refresh that doesn't immediately clear peers
          await peerDiscovery.refreshNeighbors();
        } else {
          _lastInterfaceCount = currentInterfaces.length;
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
      port: AppSettings.port,
      platform: 'Windows',
      system: 'Local',
      lastSeen: DateTime.now(),
    );
  }
}