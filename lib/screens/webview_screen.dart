// lib/screens/webview_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 – Master Command Center (WebView HUD)
//
// Features a PGTools-style stateful button that:
// 1. Synchronously launches the game and the Sovereign background bot.
// 2. Kills the engine and resets auto-catch when stopped.
// 3. Syncs with the background service to reflect the current Warden state.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/sovereign_theme.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  WebViewController? _controller;
  bool _isZygardeUp     = false;
  bool _isBotRunning    = false;
  String _activeState   = 'Idle';
  String _username      = 'Unknown';
  int _targetCount      = 0;
  
  // ── HUD Sync ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _listenToHudUpdates();
    _checkServerStatus();
  }

  void _listenToHudUpdates() {
    FlutterBackgroundService().on('hudUpdate').listen((data) {
      if (data != null && mounted) {
        setState(() {
          _activeState = data['state'] ?? 'Idle';
          _username    = data['username'] ?? 'Unknown';
          _targetCount = data['targets'] ?? 0;
          
          // Sync bot running state based on background state machine
          if (_activeState == 'Idle' || _activeState == 'MaxLimitReached') {
            _isBotRunning = false;
          } else {
            _isBotRunning = true;
          }
        });
      }
    });
  }

  Future<void> _checkServerStatus() async {
    // Simple polling for the local 8080 server
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Note: In a real app, use a proper health-check. 
      // For this UI, the background service already does this.
    });
  }

  // ── Master Control Actions ─────────────────────────────────────────────────
  void _toggleMasterEngine() {
    if (_isBotRunning) {
      _stopEngine();
    } else {
      _startEngine();
    }
  }

  Future<void> _startEngine() async {
    setState(() => _isBotRunning = true);

    // 1. Launch Pokémon GO
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.nianticlabs.pokemongo',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch Pokémon GO. Is it installed?')),
        );
      }
    }

    // 2. Fire IPC to Start Bot
    FlutterBackgroundService().invoke('controlBot', {'command': 'start'});
  }

  void _stopEngine() {
    setState(() => _isBotRunning = false);

    // Fire IPC to Stop Bot
    FlutterBackgroundService().invoke('controlBot', {'command': 'stop'});
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovereignTheme.bgDeep,
      body: Stack(
        children: [
          // ── The WebView Layer ──
          _buildWebViewLayer(),

          // ── Bottom Master Controller (PGTools Style) ──
          _buildMasterOverlay(),
        ],
      ),
    );
  }

  Widget _buildWebViewLayer() {
    // If bot isn't running, show the offline state
    if (!_isBotRunning && _activeState != 'Harvesting') {
      return _buildOfflinePlaceholder();
    }

    return WebViewWidget(
      controller: WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(SovereignTheme.bgDeep)
        ..loadRequest(Uri.parse('http://localhost:8080')),
    );
  }

  Widget _buildOfflinePlaceholder() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: SovereignTheme.bgGradient),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_outlined,
              color: SovereignTheme.accentViolet, size: 80),
          const SizedBox(height: 24),
          const Text(
            'SOVEREIGN ENGINE OFFLINE',
            style: TextStyle(
              color: SovereignTheme.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for Master Command Initialization...',
            style: TextStyle(color: SovereignTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterOverlay() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Status Bar ──
          _buildHudStatus(),
          const SizedBox(height: 12),
          // ── THE MASTER BUTTON ──
          _MasterButton(
            isRunning: _isBotRunning,
            onTap: _toggleMasterEngine,
          ),
        ],
      ),
    );
  }

  Widget _buildHudStatus() {
    Color stateColor = SovereignTheme.accentCyan;
    if (_activeState == 'MaxLimitReached') stateColor = SovereignTheme.danger;
    if (_activeState == 'Jumping') stateColor = SovereignTheme.accentViolet;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      borderRadius: 12,
      child: Row(
        children: [
          CircleAvatar(
            radius: 4,
            backgroundColor: _isBotRunning ? SovereignTheme.success : SovereignTheme.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_username.toUpperCase(),
                    style: const TextStyle(
                        color: SovereignTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                Text(_activeState,
                    style: TextStyle(
                        color: stateColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TARGETS',
                  style: TextStyle(color: SovereignTheme.textMuted, fontSize: 8)),
              Text('$_targetCount',
                  style: const TextStyle(
                      color: SovereignTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _MasterButton extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onTap;

  const _MasterButton({required this.isRunning, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 64,
        decoration: BoxDecoration(
          gradient: isRunning
              ? const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFFC2185B)]) // Crimson Red
              : SovereignTheme.accentGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (isRunning ? Colors.red : SovereignTheme.accentViolet)
                  .withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              isRunning ? 'STOP ENGINE' : 'LAUNCH SOVEREIGN',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── GlassCard Component ──────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: SovereignTheme.glassBorder),
      ),
      child: child,
    );
  }
}
