import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state_provider.dart';
import 'services/peer_discovery_service.dart';
import 'services/file_transfer_service.dart';
import 'screens/main_screen.dart';
import 'models/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(800, 600),
    minimumSize: Size(400, 300),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ZiplineApp());
}

class ZiplineApp extends StatelessWidget {
  const ZiplineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => PeerDiscoveryService()),
        ChangeNotifierProvider(create: (_) => FileTransferService()),
      ],
      child: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          final settings = appState.settings;
          final brightness = settings?.brightness ?? Brightness.light;
          
          return MaterialApp(
            title: 'Zipline',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2196F3), // Modern blue
                brightness: brightness,
              ),
              textTheme: const TextTheme(
                headlineLarge: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.bold,
                ),
                headlineMedium: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.bold,
                ),
                titleLarge: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.w600,
                ),
                bodyLarge: TextStyle(
                  fontFamily: 'LiberationSans',
                ),
                bodyMedium: TextStyle(
                  fontFamily: 'LiberationSans',
                ),
              ),
              cardTheme: const CardThemeData(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2196F3), // Modern blue
                brightness: Brightness.dark,
              ),
              textTheme: const TextTheme(
                headlineLarge: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.bold,
                ),
                headlineMedium: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.bold,
                ),
                titleLarge: TextStyle(
                  fontFamily: 'Klill',
                  fontWeight: FontWeight.w600,
                ),
                bodyLarge: TextStyle(
                  fontFamily: 'LiberationSans',
                ),
                bodyMedium: TextStyle(
                  fontFamily: 'LiberationSans',
                ),
              ),
              cardTheme: const CardThemeData(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
            themeMode: settings?.theme == AppTheme.system 
                ? ThemeMode.system 
                : settings?.theme == AppTheme.dark 
                    ? ThemeMode.dark 
                    : ThemeMode.light,
            home: const MainScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}