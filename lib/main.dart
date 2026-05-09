// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sovereign Mobile – Entry point
//   Tab 1: Zygarde WebView
//   Tab 2: Smart Bag Logic Dashboard
//   Background: Bag Daemon foreground service (auto-starts, 60s cycles)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:permission_handler/permission_handler.dart';
import 'screens/bag_logic_screen.dart';
import 'screens/route_master_screen.dart';
import 'screens/webview_screen.dart';
import 'services/bag_service.dart';
import 'theme/sovereign_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // First-run bootstrapper
  final prefs = await SharedPreferences.getInstance();
  final isFirstRun = prefs.getBool('first_run') ?? true;

  if (isFirstRun) {
    // 1. Seed Level 70 Grind Limits
    final seedLimits = {
      '1': 0, '2': 50, '3': 300,
      '101': 0, '102': 0, '103': 0, '201': 0, '703': 0,
      '104': 100, '202': 80,
      '701': 20, '705': 50,
      '704': 999, '706': 999, '1201': 999, '1202': 999, '1101': 999, '1401': 999,
    };
    await prefs.setString('keep_limits_json', jsonEncode(seedLimits));
    await prefs.setInt('daily_catch_limit', 4500);

    // 2. Initialize Directories
    final docDir = await getApplicationDocumentsDirectory();
    final routesDir = Directory('${docDir.path}/Sovereign/Routes');
    final configsDir = Directory('${docDir.path}/Sovereign/Configs');
    if (!await routesDir.exists()) await routesDir.create(recursive: true);
    if (!await configsDir.exists()) await configsDir.create(recursive: true);

    // 3. Request Overlay Permission (The Warden Failsafe)
    if (Platform.isAndroid) {
      if (!await Permission.systemAlertWindow.isGranted) {
        await Permission.systemAlertWindow.request();
      }
    }

    await prefs.setBool('first_run', false);
  }

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor           : Colors.transparent,
    statusBarIconBrightness  : Brightness.light,
    systemNavigationBarColor : SovereignTheme.bgDeep,
  ));

  // Start background bag daemon
  await initBagService();

  runApp(const SovereignApp());
}

// ─────────────────────────────────────────────────────────────────────────────
class SovereignApp extends StatelessWidget {
  const SovereignApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title       : 'Sovereign Mobile',
      theme       : SovereignTheme.theme,
      debugShowCheckedModeBanner: false,
      home        : const _MainShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _currentIndex = 0;

  static const _kZygardeUrl = 'http://localhost:8080';
  // ↑ Change to your PC's LAN IP (e.g. http://192.168.1.50:8080)
  //   if Zygarde is running on your PC rather than on-device.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovereignTheme.bgDeep,
      extendBodyBehindAppBar: true,

      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(60),
        child: _SovereignAppBar(),
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: const [
          WebViewScreen(url: _kZygardeUrl),
          BagLogicScreen(),
          RouteMasterScreen(),
        ],
      ),
      
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: SovereignTheme.bgDeep,
          border: const Border(top: BorderSide(color: SovereignTheme.glassBorder)),
        ),
        child: BottomNavigationBar(
          backgroundColor: SovereignTheme.bgDeep,
          selectedItemColor: SovereignTheme.accentViolet,
          unselectedItemColor: Colors.white54,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: 'Bag Manager'),
            BottomNavigationBarItem(icon: Icon(Icons.route_rounded), label: 'Route Master'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom AppBar with glassmorphic blur backdrop
// ─────────────────────────────────────────────────────────────────────────────
class _SovereignAppBar extends StatelessWidget {
  const _SovereignAppBar();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: SovereignTheme.bgDeep.withOpacity(0.7),
            border: const Border(
              bottom: BorderSide(color: SovereignTheme.glassBorder),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Title row ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Row(
                    children: [
                      // Animated violet dot
                      _PulsingOrb(),
                      const SizedBox(width: 12),
                      ShaderMask(
                        shaderCallback: (b) =>
                            SovereignTheme.accentGradient.createShader(b),
                        child: Text(
                          'SOVEREIGN MOBILE',
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Daemon status chip
                      _StatusChip(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pulsing orb in the app bar ─────────────────────────────────────────────────
class _PulsingOrb extends StatefulWidget {
  @override
  State<_PulsingOrb> createState() => _PulsingOrbState();
}

class _PulsingOrbState extends State<_PulsingOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _scale = Tween(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SovereignTheme.accentViolet,
          boxShadow: [
            BoxShadow(
              color: SovereignTheme.accentViolet.withOpacity(0.8),
              blurRadius: 12, spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Daemon running status chip ─────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SovereignTheme.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SovereignTheme.success.withOpacity(0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: SovereignTheme.success, size: 7),
          SizedBox(width: 5),
          Text(
            'DAEMON LIVE',
            style: TextStyle(
              color: SovereignTheme.success,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
