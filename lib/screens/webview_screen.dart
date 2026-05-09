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

class _WebViewScreenState extends State<WebViewScreen>
    with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true; // don't reload when switching tabs

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(SovereignTheme.bgDeep)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (e) => setState(() {
          _isLoading = false;
          _error = e.description;
        }),
      ))
      ..loadRequest(Uri.parse(widget.url));
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

        // ── WebView ──
        if (_error == null)
          WebViewWidget(controller: _controller)
        else
          _buildErrorState(),

        // ── Loading shimmer ──
        if (_isLoading)
          _buildLoadingOverlay(),
      ],
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
            GradientText(
              'CONNECTING TO ZYGARDE',
              style: const TextStyle(
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

  Widget _buildErrorState() {
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
              const SizedBox(height: 20),
              _GlowButton(
                label: 'RETRY',
                icon: Icons.refresh_rounded,
                onTap: () {
                  setState(() { _error = null; _isLoading = true; });
                  _controller.loadRequest(Uri.parse(widget.url));
                },
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
