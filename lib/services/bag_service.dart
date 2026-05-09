// lib/services/bag_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sovereign Mobile – Sentinel Daemon & Reactive State Machine (The Warden)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../database/route_database.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const String _kBaseUrlKey      = 'zygarde_base_url';
const String _kLimitsKey       = 'keep_limits_json';
const String _kDefaultBase     = 'http://localhost:8080';
const int    _kCycleSeconds    = 60;
const String _kLogKey          = 'service_log';
const int    _kMaxLogLines     = 50;

enum EngineState { Idle, Jumping, SpeedLockWait, Harvesting, MaxLimitReached }

// ── Globals ──────────────────────────────────────────────────────────────────
String _activeUsername = 'Unknown';
int _failedPingCount = 0;
final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

// ── Entry-point called by flutter_background_service ─────────────────────────
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  // Initialize notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await _notifications.initialize(initializationSettings);

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackground();
    });
    service.setForegroundNotificationInfo(
      title: 'Sovereign Sentinel',
      content: 'The Warden is Active...',
    );
  }

  service.on('stopService').listen((_) => service.stopSelf());
  service.on('runNow').listen((_) async {
    await _runBagCleanup(service);
  });
  service.on('updateConfig').listen((data) async {
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

  // Start the background bag cleanup polling timer (60s cycle)
  await _runBagCleanup(service);
  Timer.periodic(const Duration(seconds: _kCycleSeconds), (_) async {
    await _runBagCleanup(service);
  });

  // Start the Reactive State Machine
  _startStateMachine(service);
}

// ── Reactive State Machine ────────────────────────────────────────────────────
Future<void> _startStateMachine(ServiceInstance service) async {
  final prefs   = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultBase;

  // 1. Initial health check & Identity Hook
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/api/player'))
        .timeout(const Duration(seconds: 2));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _activeUsername = data['username'] ?? 'Unknown';
      _log(service, '[Identity] Bound to user: $_activeUsername');
    }
  } catch (e) {
    _log(service, '[Sentinel] Zygarde Offline. Retrying in 10s...');
    await Future.delayed(const Duration(seconds: 10));
    _startStateMachine(service);
    return;
  }

  // Load the first route available for jumping
  final routes = await RouteDatabase.instance.getAllRoutes();
  List<Map<String, dynamic>> routePoints = [];
  if (routes.isNotEmpty) {
    try {
      routePoints = List<Map<String, dynamic>>.from(jsonDecode(routes.first['rawData']));
    } catch (_) {}
  }
  int currentRouteIdx = 0;

  final wsUrl = baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://') + '/ws';

  WebSocketChannel? channel;
  try {
    channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _failedPingCount = 0; // Reset on successful connect
  } catch (e) {
    _log(service, '[Sentinel] WS Connect failed. Retrying in 10s...');
    await Future.delayed(const Duration(seconds: 10));
    _startStateMachine(service);
    return;
  }

  Set<String> activeEncounters = {};
  EngineState currentState = EngineState.Idle;
  Timer? harvestTimer;

  // Function to broadcast HUD state to the UI
  void broadcastHud(double cooldownRemaining) {
    service.invoke('hudUpdate', {
      'state': currentState.name,
      'targets': activeEncounters.length,
      'cooldown': cooldownRemaining,
      'username': _activeUsername,
    });
  }

  void transitionTo(EngineState newState, [double cooldown = 0]) {
    currentState = newState;
    broadcastHud(cooldown);
  }

  Future<void> _showLimitNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sovereign_alerts',
      'Sovereign Alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      999,
      '🛑 SOVEREIGN HALTED',
      '4500 Daily Limit Reached for $_activeUsername',
      details,
    );
  }

  // The main machine loop mechanism
  Future<void> triggerStateLogic() async {
    if (currentState == EngineState.Jumping) {
      // 4500 Killswitch Check
      final dailyCatches = await RouteDatabase.instance.getDailyCatches(_activeUsername);
      if (dailyCatches >= 4500) {
        _log(service, '🛑 LIMIT REACHED: $dailyCatches/4500 for $_activeUsername');
        transitionTo(EngineState.MaxLimitReached);
        await _showLimitNotification();
        
        // Turn Auto-catch OFF
        try {
          channel?.sink.add(jsonEncode({
            "type": "action", 
            "action": "settings.set", 
            "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": false}
          }));
        } catch (_) {}
        return;
      }

      if (routePoints.isEmpty) {
        _log(service, 'No route loaded. Staying idle.');
        transitionTo(EngineState.Idle);
        return;
      }
      
      final nextPoint = routePoints[currentRouteIdx];
      currentRouteIdx = (currentRouteIdx + 1) % routePoints.length;
      final cooldownSec = nextPoint['cooldown'] as double;
      final lat = nextPoint['lat'] as double;
      final lng = nextPoint['lng'] as double;

      _log(service, '⚡ Jumping to $lat, $lng');
      
      try {
        channel?.sink.add(jsonEncode({
          'type': 'action',
          'action': 'location.set',
          'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
          'payload': {'lat': lat, 'lng': lng}
        }));
        
        channel?.sink.add(jsonEncode({
          "type": "action", 
          "action": "settings.set", 
          "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": false}
        }));
      } catch (e) {
        _log(service, 'Failed to send jump commands: $e');
      }

      transitionTo(EngineState.SpeedLockWait, cooldownSec);
      await Future.delayed(Duration(milliseconds: (cooldownSec * 1000).toInt()));
      
      try {
        channel?.sink.add(jsonEncode({
          "type": "action", 
          "action": "settings.set", 
          "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": true}
        }));
      } catch (_) {}
      
      transitionTo(EngineState.Harvesting);
      
      harvestTimer?.cancel();
      harvestTimer = Timer(const Duration(seconds: 45), () {
        if (currentState == EngineState.Harvesting) {
          _log(service, 'Harvest Failsafe triggered. Forcing jump.');
          transitionTo(EngineState.Jumping);
          triggerStateLogic();
        }
      });
      
      if (activeEncounters.isEmpty) {
        harvestTimer?.cancel();
        transitionTo(EngineState.Jumping);
        triggerStateLogic();
      }
    }
  }

  // Listen to WebSocket
  channel.stream.listen((message) {
    try {
      final decoded = jsonDecode(message);
      
      // Catch Logger (Phase 5)
      // Detect successful catch in telemetry or state stream
      // Typical Zygarde catch event: {type: "telemetry", payload: {type: "catch", success: true, ...}}
      if (decoded['type'] == 'telemetry' && decoded['payload'] != null) {
        final p = decoded['payload'];
        if (p['type'] == 'catch' && p['success'] == true) {
          RouteDatabase.instance.insertCatch(_activeUsername, DateTime.now().millisecondsSinceEpoch);
          _log(service, '🎯 Catch logged for $_activeUsername');
        }
      }

      if (decoded['type'] == 'map' && decoded['payload'] != null) {
        final payload = decoded['payload'];
        bool changed = false;
        
        if (payload['pokemon'] != null) {
          for (var p in payload['pokemon']) {
            final id = p['encounter_id'].toString();
            if (!activeEncounters.contains(id)) {
              activeEncounters.add(id);
              changed = true;
            }
          }
        }
        
        if (payload['removed_pokemon'] != null) {
          for (var p in payload['removed_pokemon']) {
            if (activeEncounters.contains(p.toString())) {
              activeEncounters.remove(p.toString());
              changed = true;
            }
          }
        }
        
        if (changed) {
          broadcastHud(0);
          if (currentState == EngineState.Harvesting && activeEncounters.isEmpty) {
            harvestTimer?.cancel();
            transitionTo(EngineState.Jumping);
            triggerStateLogic();
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }, onDone: () {
    _log(service, 'WebSocket closed. Entering Auto-Revive ping loop...');
    _startAutoRevivePingLoop(service);
  }, onError: (err) {
    _log(service, 'WebSocket error: $err. Entering Auto-Revive ping loop...');
    _startAutoRevivePingLoop(service);
  });

  if (routePoints.isNotEmpty) {
    transitionTo(EngineState.Jumping);
    triggerStateLogic();
  } else {
    transitionTo(EngineState.Idle);
  }
}

// ── Auto-Revive Logic (Phase 5) ───────────────────────────────────────────────
Future<void> _startAutoRevivePingLoop(ServiceInstance service) async {
  final prefs   = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultBase;
  
  _failedPingCount = 0;
  
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    try {
      final response = await http
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        // Server is back!
        timer.cancel();
        _log(service, '[Auto-Revive] Server detected. Reconnecting...');
        _startStateMachine(service);
      } else {
        throw Exception();
      }
    } catch (_) {
      _failedPingCount++;
      _log(service, '[Auto-Revive] Ping failed ($_failedPingCount/3)');
      
      if (_failedPingCount >= 3) {
        _log(service, '⚠️ Game Crash Detected. Firing SU Hard-Reset & Auto-Revive...');
        _failedPingCount = 0;
        
        // 1. Root Hard-Kill (Phase 5.1)
        try {
          await Process.run('su', ['-c', 'am force-stop com.nianticlabs.pokemongo']);
          _log(service, '  ✓ Force-stopped game via SU');
        } catch (e) {
          _log(service, '  ✗ SU Force-stop failed (device not rooted?): $e');
        }

        // 2. Launch Pokémon GO
        try {
          const intent = AndroidIntent(
            action: 'android.intent.action.MAIN',
            package: 'com.nianticlabs.pokemongo',
            componentName: 'com.nianticlabs.pokemongo.UnityMainActivity',
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          await intent.launch();
        } catch (e) {
          _log(service, '  ✗ Auto-Revive launch failed: $e');
        }
      }
    }
  });
}

// ── Independent Bag Cleanup Cycle ─────────────────────────────────────────────
Future<void> _runBagCleanup(ServiceInstance service) async {
  final prefs   = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultBase;
  final raw     = prefs.getString(_kLimitsKey) ?? '{}';

  Map<int, int> limits = {};
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    decoded.forEach((k, v) => limits[int.tryParse(k) ?? -1] = (v as num).toInt());
  } catch (_) {}

  if (limits.isEmpty) return;

  try {
    await http
        .get(Uri.parse('$baseUrl/api/player'))
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    return;
  }

  try {
    final response = await http
        .get(Uri.parse('$baseUrl/api/item/all'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return;

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

    if (trashList.isNotEmpty) {
      _log(service, '[${_ts()}] Cleaning ${trashList.length} type(s)...');
      await _discardViaWebSocket(baseUrl, trashList, service);
    }
    service.invoke('cycleResult', {'log': prefs.getString(_kLogKey) ?? ''});

  } catch (e) {
    _log(service, '[${_ts()}] ✗ Bag Cycle failed: $e');
  }
}

Future<void> _discardViaWebSocket(
  String baseUrl,
  List<Map<String, dynamic>> trashList,
  ServiceInstance service,
) async {
  final wsUrl = baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://') + '/ws';

  WebSocketChannel? channel;
  try {
    channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    for (final entry in trashList) {
      try {
        final payload = jsonEncode({
          'type'     : 'action',
          'action'   : 'item.recycle',
          'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
          'payload'  : {
            'itemId': entry['id'],
            'amount': entry['excess'],
          }
        });
        channel.sink.add(payload);
        _log(service, '  ✓ Discarded ${entry["excess"]}x ${entry["name"]}');
        await Future.delayed(const Duration(milliseconds: 100));
      } on WebSocketChannelException catch (e) {
        _log(service, '  ✗ Game crashed or socket dropped: $e');
        break;
      } catch (e) {
        _log(service, '  ✗ Error during discard: $e');
        break;
      }
    }
  } catch (e) {
    _log(service, '  ✗ WebSocket error: $e');
  } finally {
    await channel?.sink.close();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _ts() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}';
}

Future<void> _log(ServiceInstance service, String msg) async {
  final prefs   = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kLogKey) ?? '';
  final lines    = existing.isEmpty ? <String>[] : existing.split('\n');
  lines.add(msg);
  if (lines.length > _kMaxLogLines) lines.removeRange(0, lines.length - _kMaxLogLines);
  await prefs.setString(_kLogKey, lines.join('\n'));
  service.invoke('logLine', {'msg': msg});
}

Future<void> initBagService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart          : onServiceStart,
      autoStart        : true,
      isForegroundMode : true,
      notificationChannelId: 'sovereign_bag_channel',
      initialNotificationTitle: 'Sovereign Sentinel',
      initialNotificationContent: 'The Warden is active...',
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
