import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/peer_discovery_service.dart';
import '../services/file_transfer_service.dart';
import '../services/progress_dialog_manager.dart';
import '../services/network_utility.dart';
import '../widgets/network_warning_dialog.dart';
import '../main.dart';
import '../widgets/tab_bar_widget.dart';
import '../widgets/tool_bar_widget.dart';
import 'buddies_page.dart';
import 'recent_page.dart';
import 'about_page.dart';
import 'progress_page.dart';
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
        // Hide progress dialog after showing completion briefly
        if (mounted) {
          ProgressDialogManager.instance.updateProgress(session);
          ProgressDialogManager.instance.hideProgressWithDelay();
          
          // Switch to recent page to show completed transfer
          setState(() {
            _currentPageIndex = 1;
          });
        }
      });

      fileTransfer.onSessionFailed.listen((session) {
        // Hide progress dialog and show error
        if (mounted) {
          ProgressDialogManager.instance.hideProgress();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transfer failed: ${session.error ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });

    } catch (e) {
      appState.setError(e.toString());
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          if (!appState.isInitialized) {
            if (appState.errorMessage != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Initialization Error',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appState.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _initializeServices,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            } else {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Initializing Zipline...'),
                  ],
                ),
              );
            }
          }

          return Column(
            children: [
              if (!_showSettings && !_showIpPage)
                ZiplineTabBar(
                  currentIndex: _currentPageIndex,
                  onTabChanged: _onTabChanged,
                ),
              Expanded(
                child: _buildCurrentPage(),
              ),
              if (!_showSettings && !_showIpPage)
                ZiplineToolBar(
                  onIpPressed: _showIpList,
                  onSettingsPressed: _showSettingsPage,
                ),
            ],
          );
        },
      ),
    );
  }
}