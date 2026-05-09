// lib/screens/bag_logic_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 – Smart Bag Logic Dashboard
//
// Displays a reactive ListView of items. Each row has:
//   [Icon] | [Item Name] | [Glass TextField for numeric keep-limit]
//
// Limits are saved to SharedPreferences and hot-synced to the background
// service via flutter_background_service's invoke() bridge.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../theme/sovereign_theme.dart';

// ── Item model ────────────────────────────────────────────────────────────────
class _ItemEntry {
  final int    id;
  final String name;
  final String emoji;
  int          limit;
  late final TextEditingController ctrl;

  _ItemEntry({
    required this.id,
    required this.name,
    required this.emoji,
    this.limit = 0,
  }) {
    ctrl = TextEditingController(text: limit == 0 ? '' : '$limit');
  }

  void dispose() => ctrl.dispose();
}

// ── Category & emoji mapping ───────────────────────────────────────────────────
String _emojiFor(int id, String name) {
  if (id <= 4)            return '🎱'; // balls
  if (id >= 101 && id <= 104) return '💊'; // potions
  if (id >= 201 && id <= 202) return '💎'; // revives
  if (id == 301)          return '🥚'; // lucky egg
  if (id >= 401 && id <= 404) return '🕯️'; // lures / incense
  if (id >= 701 && id <= 708) return '🍒'; // berries
  if (id >= 901 && id <= 906) return '🌟'; // evolution items
  if (id >= 1101 && id <= 1202) return '📀'; // TMs / Rare Candies
  if (id >= 1401) return '🎒'; // incubators
  return '📦';
}

// ── Category label ─────────────────────────────────────────────────────────────
String _categoryFor(int id) {
  if (id <= 4)                  return 'Poké Balls';
  if (id >= 101 && id <= 104)   return 'Potions';
  if (id >= 201 && id <= 202)   return 'Revives';
  if (id == 301)                return 'Special';
  if (id >= 401 && id <= 404)   // Lures & Incense
                                return 'Lures & Incense';
  if (id >= 701 && id <= 708)   return 'Berries';
  if (id >= 901 && id <= 906)   return 'Evolution Items';
  if (id >= 1101 && id <= 1202) return 'Treasures';
  if (id >= 1401) return 'Utility';
  return 'Other';
}

// ─────────────────────────────────────────────────────────────────────────────
class BagLogicScreen extends StatefulWidget {
  const BagLogicScreen({super.key});

  @override
  State<BagLogicScreen> createState() => _BagLogicScreenState();
}

class _BagLogicScreenState extends State<BagLogicScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── State ──────────────────────────────────────────────────────────────────
  late List<_ItemEntry> _entries;
  bool _loading        = true;
  bool _saving         = false;
  bool _running        = false;
  final List<String> _logs = [];
  final ScrollController _logScroll = ScrollController();
  String _baseUrl      = 'http://localhost:8080';
  final TextEditingController _catchLimitCtrl = TextEditingController(text: '4500');

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _buildEntries();
    _loadSaved();
    _listenToService();
  }

  @override
  void dispose() {
    for (final e in _entries) e.dispose();
    _catchLimitCtrl.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  void _buildEntries() {
    _entries = masterItemDict.entries.map((entry) {
      final id = entry.key;
      final name = entry.value;
      return _ItemEntry(
        id   : id,
        name : name,
        emoji: _emojiFor(id, name),
      );
    }).toList();
  }

  Future<void> _loadSaved() async {
    final prefs   = await SharedPreferences.getInstance();
    final raw     = prefs.getString('keep_limits_json') ?? '{}';
    final baseUrl = prefs.getString('zygarde_base_url');
    final catchLimit = prefs.getInt('daily_catch_limit') ?? 4500;
    
    if (baseUrl != null) _baseUrl = baseUrl;

    Map<String, dynamic> saved = {};
    try { saved = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}

    setState(() {
      _catchLimitCtrl.text = '$catchLimit';
      for (final e in _entries) {
        final v = saved[e.id.toString()];
        if (v != null) {
          e.limit = (v as num).toInt();
          e.ctrl.text = '${e.limit}';
        }
      }
      final savedLog = prefs.getString('service_log') ?? '';
      if (savedLog.isNotEmpty) {
        _logs.addAll(savedLog.split('\n').where((l) => l.isNotEmpty));
      }
      _loading = false;
    });
  }

  void _listenToService() {
    final service = FlutterBackgroundService();
    service.on('logLine').listen((data) {
      if (data != null && mounted) {
        setState(() {
          _logs.add(data['msg'] as String? ?? '');
          if (_logs.length > 50) _logs.removeAt(0);
        });
        _scrollLog();
      }
    });
    service.on('cycleResult').listen((_) {
      if (mounted) setState(() => _running = false);
    });
  }

  void _scrollLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _saveAndApply() async {
    setState(() => _saving = true);

    final limits = <String, int>{};
    for (final e in _entries) {
      final v = int.tryParse(e.ctrl.text.trim());
      if (v != null && v >= 0) limits[e.id.toString()] = v;
    }

    final catchLimit = int.tryParse(_catchLimitCtrl.text.trim()) ?? 4500;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('keep_limits_json', jsonEncode(limits));
    await prefs.setString('zygarde_base_url', _baseUrl);
    await prefs.setInt('daily_catch_limit', catchLimit);

    // Push to background service
    FlutterBackgroundService().invoke('updateConfig', {
      'limits' : limits,
      'baseUrl': _baseUrl,
      'catchLimit': catchLimit,
    });

    setState(() {
      _saving = false;
      _logs.add('[${_ts()}] ✓ Config saved & sent to daemon.');
      if (_logs.length > 50) _logs.removeAt(0);
    });
    _scrollLog();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SovereignTheme.accentViolet,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Limits saved & daemon updated', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  void _runNow() {
    setState(() => _running = true);
    FlutterBackgroundService().invoke('runNow');
    _logs.add('[${_ts()}] ⚡ Manual cycle triggered…');
    _scrollLog();
  }

  Future<void> _showUrlDialog() async {
    final ctrl = TextEditingController(text: _baseUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovereignTheme.bgLayer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Zygarde Server URL',
            style: TextStyle(color: SovereignTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: SovereignTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'http://192.168.x.x:8080',
            hintStyle: TextStyle(color: SovereignTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: SovereignTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _baseUrl = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save',
                style: TextStyle(color: SovereignTheme.accentViolet)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
        color: SovereignTheme.accentViolet,
      ));
    }

    // Group by category
    final grouped = <String, List<_ItemEntry>>{};
    for (final e in _entries) {
      final cat = _categoryFor(e.id);
      grouped.putIfAbsent(cat, () => []).add(e);
    }
    final categories = grouped.keys.toList();

    return Container(
      decoration: const BoxDecoration(gradient: SovereignTheme.bgGradient),
      child: Column(
        children: [
          // ── Header bar ──
          _buildHeader(),

          // ── Item list ──
          Expanded(
            child: AnimationLimiter(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: categories.length + 1, // +1 for the Catch Limit card
                itemBuilder: (ctx, idx) {
                  if (idx == 0) {
                    return _buildWardenSettings();
                  }
                  
                  final catIdx = idx - 1;
                  final cat   = categories[catIdx];
                  final items = grouped[cat]!;
                  return AnimationConfiguration.staggeredList(
                    position: catIdx,
                    duration: const Duration(milliseconds: 375),
                    child: SlideAnimation(
                      verticalOffset: 30,
                      child: FadeInAnimation(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CategoryHeader(label: cat),
                            ...items.map((e) => _ItemRow(entry: e)),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Log panel ──
          _buildLogPanel(),

          // ── Bottom action bar ──
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 12,
        child: Row(
          children: [
            const Icon(Icons.settings_suggest_rounded,
                color: SovereignTheme.accentViolet, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SMART BAG MANAGER',
                      style: TextStyle(
                          color: SovereignTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          fontSize: 13)),
                  Text(_baseUrl,
                      style: const TextStyle(
                          color: SovereignTheme.textMuted, fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _showUrlDialog,
              icon: const Icon(Icons.edit_rounded,
                  color: SovereignTheme.accentCyan, size: 18),
              tooltip: 'Edit server URL',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWardenSettings() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: 12,
        child: Row(
          children: [
            const Icon(Icons.shield_rounded, color: SovereignTheme.accentCyan, size: 24),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DAILY CATCH LIMIT',
                      style: TextStyle(
                          color: SovereignTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                  Text('Warden Killswitch Trigger',
                      style: TextStyle(color: SovereignTheme.textMuted, fontSize: 10)),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              height: 48,
              child: TextField(
                controller: _catchLimitCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SovereignTheme.accentCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  hintText: '4500',
                  hintStyle: TextStyle(color: SovereignTheme.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      height: 110,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SovereignTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Row(
              children: const [
                Icon(Icons.terminal_rounded,
                    color: SovereignTheme.accentCyan, size: 13),
                SizedBox(width: 6),
                Text('DAEMON LOG',
                    style: TextStyle(
                        color: SovereignTheme.accentCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
              ],
            ),
          ),
          const Divider(height: 6, color: SovereignTheme.glassBorder),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('No log entries yet.',
                        style: TextStyle(
                            color: SovereignTheme.textMuted, fontSize: 11)))
                : ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Text(
                      _logs[i],
                      style: TextStyle(
                        color: _logs[i].contains('✓') || _logs[i].contains('Optimized')
                            ? SovereignTheme.success
                            : _logs[i].contains('✗') || _logs[i].contains('error')
                                ? SovereignTheme.danger
                                : SovereignTheme.textMuted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: SovereignTheme.bgDeep,
        border: const Border(top: BorderSide(color: SovereignTheme.glassBorder)),
      ),
      child: Row(
        children: [
          // Run Now
          Expanded(
            child: _OutlineButton(
              label: _running ? 'RUNNING…' : 'RUN NOW',
              icon: _running
                  ? Icons.hourglass_top_rounded
                  : Icons.play_arrow_rounded,
              color: SovereignTheme.accentCyan,
              onTap: _running ? null : _runNow,
            ),
          ),
          const SizedBox(width: 12),
          // Save & Apply
          Expanded(
            flex: 2,
            child: _GradientButton(
              label: _saving ? 'SYNCING…' : 'SYNC & ARM',
              icon: _saving ? Icons.hourglass_top_rounded : Icons.sync_rounded,
              onTap: _saving ? null : _saveAndApply,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              gradient: SovereignTheme.accentGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: SovereignTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.entry});
  final _ItemEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 12,
        child: Row(
          children: [
            // ── Emoji icon ──
            Text(entry.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),

            // ── Name + ID ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(
                      color: SovereignTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'ID: ${entry.id}',
                    style: const TextStyle(
                      color: SovereignTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

            // ── Smart Box numeric input ──
            SizedBox(
              width: 80,
              height: 48,
              child: TextField(
                controller: entry.ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SovereignTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                decoration: const InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(color: SovereignTheme.textMuted),
                  labelText: 'Keep',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.icon, this.onTap});
  final String    label;
  final IconData  icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: SovereignTheme.accentGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: SovereignTheme.accentViolet.withOpacity(0.45),
                blurRadius: 18, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
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
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton(
      {required this.label, required this.icon, required this.color, this.onTap});
  final String    label;
  final IconData  icon;
  final Color     color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

String _ts() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2,'0')}:'
      '${now.minute.toString().padLeft(2,'0')}:'
      '${now.second.toString().padLeft(2,'0')}';
}
