// lib/screens/webview_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 – Zygarde WebUI embedded in a full-screen WebView.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/sovereign_theme.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url});
  final String url;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class _WebViewScreenState extends State<WebViewScreen>
    with AutomaticKeepAliveClientMixin {
  WebViewController? _controller;
  bool _isChecking = true;
  bool _isOffline = true;
  String? _error;

  @override
  bool get wantKeepAlive => true; // don't reload when switching tabs

  String _hudState = 'Idle';
  int _hudTargets = 0;
  double _hudCooldown = 0.0;

  @override
  void initState() {
    super.initState();
    _checkServerHealth();
    
    FlutterBackgroundService().on('hudUpdate').listen((event) {
      if (mounted && event != null) {
        setState(() {
          _hudState = event['state'] as String? ?? 'Idle';
          _hudTargets = event['targets'] as int? ?? 0;
          _hudCooldown = (event['cooldown'] as num?)?.toDouble() ?? 0.0;
        });
      }
    });
  }

  Future<void> _checkServerHealth() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    try {
      final response = await http
          .get(Uri.parse('http://localhost:8080/api/player'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200 || response.statusCode == 404) {
        // Server is reachable (even if 404, the server process is alive)
        _initWebView();
        if (mounted) {
          setState(() {
            _isOffline = false;
            _isChecking = false;
          });
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOffline = true;
          _isChecking = false;
          _error = 'Zygarde server is unreachable.';
        });
      }
    }
  }

  void _initWebView() {
    if (_controller != null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(SovereignTheme.bgDeep)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isChecking = true),
        onPageFinished: (_) => setState(() => _isChecking = false),
        onWebResourceError: (e) => setState(() {
          _isChecking = false;
          _error = e.description;
          _isOffline = true;
        }),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _launchGame() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.nianticlabs.pokemongo',
        componentName: 'com.nianticlabs.pokemongo.UnityMainActivity',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SovereignTheme.danger,
            content: const Text('Pokémon GO is not installed or could not be launched.', style: TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        // ── Background gradient ──
        Container(
          decoration: const BoxDecoration(
            gradient: SovereignTheme.bgGradient,
          ),
        ),

        // ── Main Content ──
        if (_isOffline)
          _buildOfflineState()
        else if (_controller != null)
          WebViewWidget(controller: _controller!),

        // ── Loading shimmer ──
        if (_isChecking)
          _buildLoadingOverlay(),

        // ── Sovereign HUD ──
        if (!_isOffline)
          _buildSovereignHud(),
      ],
    );
  }

  Widget _buildSovereignHud() {
    return Positioned(
      top: 80,
      right: 16,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _hudState == 'Harvesting' ? Icons.bolt_rounded :
                  _hudState == 'Jumping' ? Icons.rocket_launch_rounded :
                  _hudState == 'SpeedLockWait' ? Icons.hourglass_top_rounded : Icons.pause_circle_filled_rounded,
                  color: SovereignTheme.accentViolet,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  _hudState.toUpperCase(),
                  style: const TextStyle(color: SovereignTheme.accentViolet, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('🎯 Targets: $_hudTargets', style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 2),
            Text('⏳ Cooldown: ${_hudCooldown.toStringAsFixed(1)}s', style: const TextStyle(color: SovereignTheme.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: SovereignTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(SovereignTheme.accentViolet),
              ),
            ),
            const SizedBox(height: 20),
            const GradientText(
              'CONNECTING TO ZYGARDE',
              style: TextStyle(
                fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.url,
              style: const TextStyle(
                color: SovereignTheme.textMuted, fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: SovereignTheme.danger, size: 48),
              const SizedBox(height: 16),
              const GradientText(
                'ZYGARDE OFFLINE',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Could not connect to ${widget.url}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: SovereignTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 32),
              _GlowButton(
                label: 'LAUNCH POKÉMON GO',
                icon: Icons.rocket_launch_rounded,
                onTap: _launchGame,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _checkServerHealth,
                icon: const Icon(Icons.refresh_rounded, color: SovereignTheme.textMuted, size: 16),
                label: const Text('Retry Connection', style: TextStyle(color: SovereignTheme.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared glow button ─────────────────────────────────────────────────────────
class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: SovereignTheme.accentGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: SovereignTheme.accentViolet.withOpacity(0.4),
              blurRadius: 16, spreadRadius: 0, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
