// lib/services/bag_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sovereign Mobile – Bag Daemon (Dart port of bagmanager.py)
// Runs as an Android foreground service via flutter_background_service.
// Every 60 s it:
//   1. Reads keep-limits from SharedPreferences
//   2. GETs /api/item/all from the Zygarde server
//   3. Sends item.recycle WebSocket frames for every over-limit item
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// ── Constants ─────────────────────────────────────────────────────────────────
const String _kBaseUrlKey      = 'zygarde_base_url';
const String _kLimitsKey       = 'keep_limits_json';
const String _kDefaultBase     = 'http://localhost:8080';
const int    _kCycleSeconds    = 60;
const String _kLogKey          = 'service_log';
const int    _kMaxLogLines     = 50;

// ── Entry-point called by flutter_background_service ─────────────────────────
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  // Android: become a foreground service immediately.
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackground();
    });
    service.setForegroundNotificationInfo(
      title: 'Sovereign Bag Daemon',
      content: 'Running – next cycle in ${_kCycleSeconds}s',
    );
  }

  // Listen for UI → service messages
  service.on('stopService').listen((_) => service.stopSelf());
  service.on('runNow').listen((_) async {
    await _runCycle(service);
  });
  service.on('updateConfig').listen((data) async {
    // data = {'limits': {'1': 50, '3': 100, ...}, 'baseUrl': 'http://...'}
    if (data == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (data['limits'] != null) {
      await prefs.setString(_kLimitsKey, jsonEncode(data['limits']));
    }
    if (data['baseUrl'] != null) {
      await prefs.setString(_kBaseUrlKey, data['baseUrl'] as String);
    }
    _log(service, 'Config updated via UI.');
  });

  // Initial cycle + periodic timer
  await _runCycle(service);

  Timer.periodic(const Duration(seconds: _kCycleSeconds), (_) async {
    await _runCycle(service);
  });
}

// ── Main cycle ────────────────────────────────────────────────────────────────
Future<void> _runCycle(ServiceInstance service) async {
  final prefs   = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultBase;
  final raw     = prefs.getString(_kLimitsKey) ?? '{}';

  Map<int, int> limits = {};
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    decoded.forEach((k, v) => limits[int.tryParse(k) ?? -1] = (v as num).toInt());
  } catch (_) {}

  if (limits.isEmpty) {
    _log(service, '[${_ts()}] No limits configured yet.');
    return;
  }

  try {
    final response = await http
        .get(Uri.parse('$baseUrl/api/item/all'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      _log(service, '[${_ts()}] API error: ${response.statusCode}');
      return;
    }

    final body  = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? [];

    final trashList = <Map<String, dynamic>>[];
    for (final item in items) {
      final id     = item['itemId'] as int?;
      final amt    = item['amount'] as int? ?? 0;
      final name   = item['itemName'] as String? ?? 'Item $id';
      if (id != null && limits.containsKey(id) && amt > limits[id]!) {
        trashList.add({'id': id, 'name': name, 'excess': amt - limits[id]!});
      }
    }

    if (trashList.isEmpty) {
      _log(service, '[${_ts()}] ✓ Bag optimized.');
    } else {
      _log(service, '[${_ts()}] Cleaning ${trashList.length} type(s)...');
      await _discardViaWebSocket(baseUrl, trashList, service);
    }

    // Push result to UI
    service.invoke('cycleResult', {'log': prefs.getString(_kLogKey) ?? ''});

  } catch (e) {
    _log(service, '[${_ts()}] ✗ Cycle failed: $e');
  }

  // Update notification
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Sovereign Bag Daemon',
      content: 'Last run: ${_ts()}',
    );
  }
}

// ── WebSocket discard (mirrors discard_items_ws in bagmanager.py) ─────────────
Future<void> _discardViaWebSocket(
  String baseUrl,
  List<Map<String, dynamic>> trashList,
  ServiceInstance service,
) async {
  final wsUrl = baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://') +
      '/ws';

  WebSocket? ws;
  try {
    ws = await WebSocket.connect(wsUrl)
        .timeout(const Duration(seconds: 5));

    for (final entry in trashList) {
      final payload = jsonEncode({
        'type'     : 'action',
        'action'   : 'item.recycle',
        'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
        'payload'  : {
          'itemId': entry['id'],
          'amount': entry['excess'],
        }
      });
      ws.add(payload);
      _log(service, '  ✓ Discarded ${entry["excess"]}x ${entry["name"]}');
      await Future.delayed(const Duration(milliseconds: 150));
    }
  } catch (e) {
    _log(service, '  ✗ WebSocket error: $e');
  } finally {
    await ws?.close();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _ts() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2,'0')}:'
      '${now.minute.toString().padLeft(2,'0')}:'
      '${now.second.toString().padLeft(2,'0')}';
}

Future<void> _log(ServiceInstance service, String msg) async {
  // Persist a rolling log buffer in SharedPreferences
  final prefs   = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kLogKey) ?? '';
  final lines    = existing.isEmpty ? <String>[] : existing.split('\n');
  lines.add(msg);
  if (lines.length > _kMaxLogLines) lines.removeRange(0, lines.length - _kMaxLogLines);
  await prefs.setString(_kLogKey, lines.join('\n'));
  // Also push to UI if listening
  service.invoke('logLine', {'msg': msg});
}

// ── Public helper: initialise + start the service ─────────────────────────────
Future<void> initBagService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart          : onServiceStart,
      autoStart        : true,
      isForegroundMode : true,
      notificationChannelId: 'sovereign_bag_channel',
      initialNotificationTitle: 'Sovereign Bag Daemon',
      initialNotificationContent: 'Starting…',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart  : false,
      onForeground: onServiceStart,
    ),
  );

  service.startService();
}
