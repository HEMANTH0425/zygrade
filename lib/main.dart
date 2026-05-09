// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sovereign Mobile – Entry point
//   Tab 1: Zygarde WebView
//   Tab 2: Smart Bag Logic Dashboard
//   Background: Bag Daemon foreground service (auto-starts, 60s cycles)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/bag_logic_screen.dart';
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

class _MainShellState extends State<_MainShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _kZygardeUrl = 'http://localhost:8080';
  // ↑ Change to your PC's LAN IP (e.g. http://192.168.1.50:8080)
  //   if Zygarde is running on your PC rather than on-device.

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovereignTheme.bgDeep,
      extendBodyBehindAppBar: true,

      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: _SovereignAppBar(tabCtrl: _tabCtrl),
      ),

      body: TabBarView(
        controller: _tabCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          WebViewScreen(url: _kZygardeUrl),
          BagLogicScreen(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom AppBar with glassmorphic blur backdrop
// ─────────────────────────────────────────────────────────────────────────────
class _SovereignAppBar extends StatelessWidget {
  const _SovereignAppBar({required this.tabCtrl});
  final TabController tabCtrl;

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
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
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

                // ── Tab bar ──
                TabBar(
                  controller: tabCtrl,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.map_rounded, size: 18),
                      text: 'Zygarde Map',
                    ),
                    Tab(
                      icon: Icon(Icons.inventory_2_rounded, size: 18),
                      text: 'Bag Logic',
                    ),
                  ],
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
