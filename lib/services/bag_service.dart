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
const String _kCatchLimitKey   = 'daily_catch_limit';
const String _kDefaultBase     = 'http://localhost:8080';
const int    _kCycleSeconds    = 60;
const String _kLogKey          = 'service_log';
const int    _kMaxLogLines     = 50;

enum EngineState { Idle, Jumping, SpeedLockWait, Harvesting, MaxLimitReached }

// ── Globals ──────────────────────────────────────────────────────────────────
String _activeUsername = 'Unknown';
int _failedPingCount = 0;
final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

// ── Bot State Globals ────────────────────────────────────────────────────────
EngineState _currentState = EngineState.Idle;
WebSocketChannel? _wsChannel;
Set<String> _activeEncounters = {};
Timer? _harvestTimer;
int _currentRouteIdx = 0;
List<Map<String, dynamic>> _routePoints = [];

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
    if (data['catchLimit'] != null) {
      await prefs.setInt(_kCatchLimitKey, data['catchLimit'] as int);
    }
    _log(service, 'Config updated via UI.');
  });

  // ── Phase 6: Master Command IPC ──
  service.on('controlBot').listen((data) async {
    if (data == null) return;
    final command = data['command'] as String?;
    
    if (command == 'start') {
      _log(service, '▶️ IPC: Start Engine Received.');
      _startStateMachine(service);
    } else if (command == 'stop') {
      _log(service, '🛑 IPC: Stop Engine Received.');
      _stopBot(service);
    }
  });

  // Start the background bag cleanup polling timer (60s cycle)
  await _runBagCleanup(service);
  Timer.periodic(const Duration(seconds: _kCycleSeconds), (_) async {
    await _runBagCleanup(service);
  });
}

// ── Bot Control ──────────────────────────────────────────────────────────────
void _stopBot(ServiceInstance service) {
  _currentState = EngineState.Idle;
  _harvestTimer?.cancel();
  
  // Disable Auto-catch via WS
  try {
    _wsChannel?.sink.add(jsonEncode({
      "type": "action", 
      "action": "settings.set", 
      "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": false}
    }));
  } catch (_) {}

  _activeEncounters.clear();
  _broadcastHud(service, 0);
  _log(service, 'Engine Frozen. Radar Cleared.');
}

void _broadcastHud(ServiceInstance service, double cooldownRemaining) {
  service.invoke('hudUpdate', {
    'state': _currentState.name,
    'targets': _activeEncounters.length,
    'cooldown': cooldownRemaining,
    'username': _activeUsername,
  });
}

// ── Reactive State Machine ────────────────────────────────────────────────────
Future<void> _startStateMachine(ServiceInstance service) async {
  final prefs   = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultBase;

  // 1. Health check & Identity
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
    _log(service, '[Sentinel] Zygarde Offline. Waiting for Auto-Revive loop...');
    _startAutoRevivePingLoop(service);
    return;
  }

  // Load the route
  final routes = await RouteDatabase.instance.getAllRoutes();
  if (routes.isNotEmpty) {
    try {
      _routePoints = List<Map<String, dynamic>>.from(jsonDecode(routes.first['rawData']));
    } catch (_) {}
  }
  _currentRouteIdx = 0;

  final wsUrl = baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://') + '/ws';

  try {
    _wsChannel?.sink.close(); // Close existing if any
    _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _failedPingCount = 0;
  } catch (e) {
    _log(service, '[Sentinel] WS Connect failed. Retrying in 5s...');
    await Future.delayed(const Duration(seconds: 5));
    _startStateMachine(service);
    return;
  }

  // Listen to WebSocket
  _wsChannel?.stream.listen((message) {
    if (_currentState == EngineState.Idle) return;

    try {
      final decoded = jsonDecode(message);
      
      if (decoded['type'] == 'map' && decoded['payload'] != null) {
        final payload = decoded['payload'];
        bool changed = false;
        
        if (payload['pokemon'] != null) {
          for (var p in payload['pokemon']) {
            final id = p['encounter_id'].toString();
            if (!_activeEncounters.contains(id)) {
              _activeEncounters.add(id);
              changed = true;
            }
          }
        }
        
        if (payload['removed_pokemon'] != null) {
          for (var p in payload['removed_pokemon']) {
            final id = p.toString();
            if (_activeEncounters.contains(id)) {
              _activeEncounters.remove(id);
              changed = true;
              
              if (_currentState == EngineState.Harvesting) {
                RouteDatabase.instance.insertCatch(_activeUsername, DateTime.now().millisecondsSinceEpoch);
              }
            }
          }
        }
        
        if (changed) {
          _broadcastHud(service, 0);
          if (_currentState == EngineState.Harvesting && _activeEncounters.isEmpty) {
            _harvestTimer?.cancel();
            _transitionTo(service, EngineState.Jumping);
            _triggerStateLogic(service, prefs);
          }
        }
      }
    } catch (e) {}
  }, onDone: () {
    if (_currentState != EngineState.Idle) {
      _log(service, 'WebSocket closed. Entering Auto-Revive loop...');
      _startAutoRevivePingLoop(service);
    }
  }, onError: (err) {
    if (_currentState != EngineState.Idle) {
      _log(service, 'WebSocket error: $err. Entering Auto-Revive loop...');
      _startAutoRevivePingLoop(service);
    }
  });

  if (_routePoints.isNotEmpty) {
    _transitionTo(service, EngineState.Jumping);
    _triggerStateLogic(service, prefs);
  } else {
    _transitionTo(service, EngineState.Idle);
  }
}

void _transitionTo(ServiceInstance service, EngineState newState, [double cooldown = 0]) {
  _currentState = newState;
  _broadcastHud(service, cooldown);
}

Future<void> _triggerStateLogic(ServiceInstance service, SharedPreferences prefs) async {
  if (_currentState == EngineState.Jumping) {
    // Killswitch Check
    final dailyLimit = prefs.getInt(_kCatchLimitKey) ?? 4500;
    final dailyCatches = await RouteDatabase.instance.getDailyCatches(_activeUsername);
    if (dailyCatches >= dailyLimit) {
      _log(service, '🛑 LIMIT REACHED: $dailyCatches/$dailyLimit for $_activeUsername');
      _transitionTo(service, EngineState.MaxLimitReached);
      _showLimitNotification(dailyLimit);
      
      try {
        _wsChannel?.sink.add(jsonEncode({
          "type": "action", 
          "action": "settings.set", 
          "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": false}
        }));
      } catch (_) {}
      return;
    }

    if (_routePoints.isEmpty) {
      _transitionTo(service, EngineState.Idle);
      return;
    }
    
    final nextPoint = _routePoints[_currentRouteIdx];
    _currentRouteIdx = (_currentRouteIdx + 1) % _routePoints.length;
    final cooldownSec = (nextPoint['cooldown'] as num?)?.toDouble() ?? 0.0;
    final lat = nextPoint['lat'] as double;
    final lng = nextPoint['lng'] as double;

    _log(service, '⚡ Jumping to $lat, $lng');
    
    try {
      _wsChannel?.sink.add(jsonEncode({
        'type': 'action',
        'action': 'location.set',
        'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
        'payload': {'lat': lat, 'lng': lng}
      }));
      
      _wsChannel?.sink.add(jsonEncode({
        "type": "action", 
        "action": "settings.set", 
        "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": false}
      }));
    } catch (e) {
      _log(service, 'Failed to send jump commands: $e');
    }

    _transitionTo(service, EngineState.SpeedLockWait, cooldownSec);
    await Future.delayed(Duration(milliseconds: (cooldownSec * 1000).toInt()));
    
    if (_currentState == EngineState.Idle) return;

    try {
      _wsChannel?.sink.add(jsonEncode({
        "type": "action", 
        "action": "settings.set", 
        "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": true}
      }));
    } catch (_) {}
    
    _transitionTo(service, EngineState.Harvesting);
    
    _harvestTimer?.cancel();
    _harvestTimer = Timer(const Duration(seconds: 45), () {
      if (_currentState == EngineState.Harvesting) {
        _log(service, 'Harvest Failsafe triggered. Forcing jump.');
        _transitionTo(service, EngineState.Jumping);
        _triggerStateLogic(service, prefs);
      }
    });
    
    if (_activeEncounters.isEmpty) {
      _harvestTimer?.cancel();
      _transitionTo(service, EngineState.Jumping);
      _triggerStateLogic(service, prefs);
    }
  }
}

// ── Auto-Revive Logic ────────────────────────────────────────────────────────
Future<void> _startAutoRevivePingLoop(ServiceInstance service) async {
  final prefs   = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultBase;
  
  _failedPingCount = 0;
  
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    if (_currentState == EngineState.Idle) {
      timer.cancel();
      return;
    }

    try {
      final response = await http
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        timer.cancel();
        _log(service, '[Auto-Revive] Server detected. Reconnecting...');
        _startStateMachine(service);
      } else {
        throw Exception();
      }
    } catch (_) {
      _failedPingCount++;
      _log(service, '[Auto-Revive] Ping failed ($_failedPingCount/8)');
      
      if (_failedPingCount >= 8) {
        _log(service, '⚠️ Game Crash Detected. Firing SU Hard-Reset & Auto-Revive...');
        _failedPingCount = 0;
        
        try {
          await Process.run('su', ['-c', 'am force-stop com.nianticlabs.pokemongo']);
        } catch (_) {}

        try {
          const intent = AndroidIntent(
            action: 'android.intent.action.MAIN',
            package: 'com.nianticlabs.pokemongo',
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          await intent.launch();
        } catch (_) {}
      }
    }
  });
}

// ── Bag Cleanup ─────────────────────────────────────────────────────────────
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
  } catch (_) {}
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
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (_) {
        break;
      }
    }
  } catch (_) {
  } finally {
    await channel?.sink.close();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String _ts() => '${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}:${DateTime.now().second.toString().padLeft(2,'0')}';

Future<void> _log(ServiceInstance service, String msg) async {
  final prefs   = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kLogKey) ?? '';
  final lines    = existing.isEmpty ? <String>[] : existing.split('\n');
  lines.add(msg);
  if (lines.length > _kMaxLogLines) lines.removeRange(0, lines.length - _kMaxLogLines);
  await prefs.setString(_kLogKey, lines.join('\n'));
  service.invoke('logLine', {'msg': msg});
}

Future<void> _showLimitNotification(int limit) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sovereign_alerts',
    'Sovereign Alerts',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: false,
    playSound: true,
    ticker: 'ticker',
  );
  const NotificationDetails details = NotificationDetails(android: androidDetails);
  await _notifications.show(
    999,
    '🛑 SOVEREIGN HALTED',
    'Daily Limit ($limit) Reached for $_activeUsername',
    details,
  );
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
