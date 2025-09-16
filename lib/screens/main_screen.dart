import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/peer_discovery_service.dart';
import '../services/file_transfer_service.dart';
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
  bool _showProgress = false;
  bool _showSettings = false;
  bool _showIpPage = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
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
      
      // Initialize file transfer service (clean up old history)
      fileTransfer.initialize();
      
      // Start file transfer server
      final transferStarted = await fileTransfer.startServer(settings.port);
      if (!transferStarted) {
        throw Exception('Failed to start file transfer server');
      }

      appState.setInitialized(true);

      // Listen to transfer events
      fileTransfer.onSessionStarted.listen((session) {
        setState(() {
          _showProgress = true;
        });
      });

      fileTransfer.onSessionCompleted.listen((session) {
        setState(() {
          _showProgress = false;
          _currentPageIndex = 1; // Switch to recent page
        });
      });

      fileTransfer.onSessionFailed.listen((session) {
        setState(() {
          _showProgress = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: ${session.error}'),
            backgroundColor: Colors.red,
          ),
        );
      });

    } catch (e) {
      appState.setError(e.toString());
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentPageIndex = index;
      _showProgress = false;
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
      _showProgress = false;
    });
  }

  Widget _buildCurrentPage() {
    if (_showProgress) {
      return const ProgressPage();
    }
    
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
              if (!_showProgress && !_showSettings && !_showIpPage)
                ZiplineTabBar(
                  currentIndex: _currentPageIndex,
                  onTabChanged: _onTabChanged,
                ),
              Expanded(
                child: _buildCurrentPage(),
              ),
              if (!_showProgress && !_showSettings && !_showIpPage)
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