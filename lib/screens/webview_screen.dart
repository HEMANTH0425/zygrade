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
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/zygarde_config.dart';

import '../theme/sovereign_theme.dart';

class WebViewScreen extends StatefulWidget {
  final String? url;
  const WebViewScreen({super.key, this.url});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  late final WebViewController _controller;
  bool _isZygardeUp     = false;
  bool _isBotRunning    = false;
  String _activeState   = 'Idle';
  String _username      = 'Unknown';
  int _targetCount      = 0;
  bool _isLoading       = true;
  bool _hasError        = false;
  
  // ── HUD Sync ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(SovereignTheme.currentBg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() { _isLoading = true; _hasError = false; }),
          onPageFinished: (_) async {
            setState(() { _isLoading = false; _isZygardeUp = true; });
            // Auto-sync when page is ready
            await _injectLatestConfig();
          },
          onWebResourceError: (error) {
            debugPrint('Sovereign: Web Error: ${error.description}');
            setState(() {
              _isLoading = false;
              _hasError = true;
              _isZygardeUp = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url ?? 'http://localhost:8080'));

    _listenToHudUpdates();
    _listenToSyncEvents();
    _listenToForceSync();
    _startServerPolling();
  }

  void _listenToForceSync() {
    FlutterBackgroundService().on('forceSync').listen((data) async {
      if (mounted) {
        _injectLatestConfig();
      }
    });
  }

  void _listenToHudUpdates() {
    FlutterBackgroundService().on('hudUpdate').listen((data) {
      if (data != null && mounted) {
        setState(() {
          _activeState = data['state'] ?? 'Idle';
          _username    = data['username'] ?? 'Unknown';
          _targetCount = data['targets'] ?? 0;
          
          if (_activeState == 'Idle' || _activeState == 'MaxLimitReached') {
            _isBotRunning = false;
          } else {
            _isBotRunning = true;
          }
        });
      }
    });
  }

  void _listenToSyncEvents() {
    FlutterBackgroundService().on('syncZygarde').listen((data) async {
      if (data != null && mounted) {
        debugPrint('Sovereign: Received sync event: $data');
        await _injectZygardeSettings(data);
      }
    });
  }

  Future<void> _injectLatestConfig() async {
    try {
      // Get the latest config from service/storage
      // In a real scenario, we'd fetch this from SharedPreferences or a global state
      // For now, we'll invoke a request to the service to send us the config
      FlutterBackgroundService().invoke('requestConfigSync');
    } catch (e) {
      debugPrint('Sovereign: Initial sync request failed: $e');
    }
  }

  Future<void> _injectZygardeSettings(Map<String, dynamic> settings) async {
    final config = ZygardeConfig.fromJson(settings);
    final String js = config.toJSInjection();

    debugPrint('Sovereign: Injecting Zygarde Settings (Manual/Auto)...');
    try {
      final result = await _controller.runJavaScriptReturningResult(js);
      debugPrint('Sovereign: Injection result: $result');
    } catch (e) {
      debugPrint('Sovereign: Injection failed: $e');
    }
  }

  void _startServerPolling() {
    // If we have an error, try to reload every 5 seconds
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_hasError) {
        _reload();
      }
    });
  }

  void _reload() {
    _controller.loadRequest(Uri.parse(widget.url ?? 'http://localhost:8080'));
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
      await Process.run('su', [
        '-c', 
        'monkey -p com.nianticlabs.pokemongo -c android.intent.category.LAUNCHER 1'
      ]);
      // Give it a moment then try to reload the webview
      Future.delayed(const Duration(seconds: 10), _reload);
    } catch (e) {
      debugPrint('Sovereign: Launch error: $e');
    }

    // 2. Fire IPC to Start Bot
    FlutterBackgroundService().invoke('controlBot', {'command': 'start'});
  }

  void _stopEngine() {
    setState(() => _isBotRunning = false);
    FlutterBackgroundService().invoke('controlBot', {'command': 'stop'});
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Detect if this is the dedicated WebUI tab (widget.url might be provided or we can check index)
    // For now, let's just make it look consistent.
    return Scaffold(
      backgroundColor: SovereignTheme.currentBg,
      body: Stack(
        children: [
          // ── The WebView Layer ──
          _buildWebViewLayer(),

          // ── Bottom Master Controller ──
          if (widget.url == null) _buildMasterOverlay(),
          
          // ── Floating Refresh for dedicated WebUI ──
          if (widget.url != null) 
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: _reload,
                backgroundColor: SovereignTheme.accentViolet.withOpacity(0.7),
                child: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebViewLayer() {
    if (_hasError) {
      return _buildOfflinePlaceholder();
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: SovereignTheme.accentViolet)),
      ],
    );
  }

  Widget _buildOfflinePlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: SovereignTheme.bgGradient),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_outlined,
              color: SovereignTheme.accentViolet, size: 80),
          const SizedBox(height: 24),
          const Text(
            'ZYGARDE SERVER OFFLINE',
            style: TextStyle(
              color: SovereignTheme.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for Pokemon GO to initialize the engine...',
            style: TextStyle(color: SovereignTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, color: SovereignTheme.accentCyan),
            label: const Text('RETRY CONNECTION', style: TextStyle(color: SovereignTheme.accentCyan)),
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
