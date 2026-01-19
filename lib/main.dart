import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/preferences_service.dart';
import 'screens/home_screen.dart';
import 'screens/mobile_home_screen.dart';
import 'screens/tablet_home_screen.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoEffectsStudioApp());
}

class VideoEffectsStudioApp extends StatelessWidget {
  const VideoEffectsStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..checkForUpdates(),
      child: MaterialApp(
        title: 'Video Effects Studio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6B4EFF),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          cardTheme: CardTheme(
            color: const Color(0xFF1E1E1E),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        home: const ResponsiveHome(),
      ),
    );
  }
}

/// Responsive wrapper that switches between desktop, tablet, and mobile layouts
class ResponsiveHome extends StatelessWidget {
  const ResponsiveHome({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine if this is truly a mobile device
        final isMobileDevice = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);
        
        // Use mobile layout for small screens or mobile devices
        if (constraints.maxWidth < 600) {
          return const MobileHomeScreen();
        }
        
        // Use tablet layout for medium screens (600-900px) or mobile devices with large screens
        if (constraints.maxWidth < 900 || isMobileDevice) {
          return const TabletHomeScreen();
        }
        
        // Use full desktop layout for larger screens
        return const HomeScreen();
      },
    );
  }
}
