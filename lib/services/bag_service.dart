// lib/services/bag_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sovereign Mobile – Sentinel Daemon & Reactive State Machine
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../database/route_database.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const String _kBaseUrlKey      = 'zygarde_base_url';
const String _kLimitsKey       = 'keep_limits_json';
const String _kDefaultBase     = 'http://localhost:8080';
const int    _kCycleSeconds    = 60;
const String _kLogKey          = 'service_log';
const int    _kMaxLogLines     = 50;

enum EngineState { Idle, Jumping, SpeedLockWait, Harvesting }

// ── Entry-point called by flutter_background_service ─────────────────────────
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackground();
    });
    service.setForegroundNotificationInfo(
      title: 'Sovereign Sentinel',
      content: 'Initializing State Machine...',
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

  // 1. Initial health check
  try {
    await http
        .get(Uri.parse('$baseUrl/api/player'))
        .timeout(const Duration(seconds: 2));
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
    });
  }

  void transitionTo(EngineState newState, [double cooldown = 0]) {
    currentState = newState;
    broadcastHud(cooldown);
  }

  // The main machine loop mechanism
  Future<void> triggerStateLogic() async {
    if (currentState == EngineState.Jumping) {
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
      
      // Send location.set
      try {
        channel?.sink.add(jsonEncode({
          'type': 'action',
          'action': 'location.set',
          'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
          'payload': {'lat': lat, 'lng': lng}
        }));
        
        // Send settings.set (Auto-catch false)
        channel?.sink.add(jsonEncode({
          "type": "action", 
          "action": "settings.set", 
          "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": false}
        }));
      } catch (e) {
        _log(service, 'Failed to send jump commands: $e');
      }

      transitionTo(EngineState.SpeedLockWait, cooldownSec);
      
      // Wait out the cooldown
      await Future.delayed(Duration(milliseconds: (cooldownSec * 1000).toInt()));
      
      // Send settings.set (Auto-catch true)
      try {
        channel?.sink.add(jsonEncode({
          "type": "action", 
          "action": "settings.set", 
          "payload": {"type": "bool", "category": "Map", "name": "Auto catch all", "value": true}
        }));
      } catch (e) {
        // ignore
      }
      
      transitionTo(EngineState.Harvesting);
      
      // Failsafe timer for harvesting
      harvestTimer?.cancel();
      harvestTimer = Timer(const Duration(seconds: 45), () {
        if (currentState == EngineState.Harvesting) {
          _log(service, 'Harvest Failsafe triggered. Forcing jump.');
          transitionTo(EngineState.Jumping);
          triggerStateLogic();
        }
      });
      
      // In case activeEncounters is ALREADY empty when we start harvesting
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
      if (decoded['type'] == 'map' && decoded['payload'] != null) {
        final payload = decoded['payload'];
        bool changed = false;
        
        // Add new encounters
        if (payload['pokemon'] != null) {
          for (var p in payload['pokemon']) {
            final id = p['encounter_id'].toString();
            if (!activeEncounters.contains(id)) {
              activeEncounters.add(id);
              changed = true;
            }
          }
        }
        
        // Remove completed encounters
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
          // If we are harvesting and just cleared the node
          if (currentState == EngineState.Harvesting && activeEncounters.isEmpty) {
            harvestTimer?.cancel();
            transitionTo(EngineState.Jumping);
            triggerStateLogic();
          }
        }
      }
    } catch (e) {
      // ignore parsing errors
    }
  }, onDone: () {
    _log(service, 'WebSocket closed. Restarting state machine...');
    Future.delayed(const Duration(seconds: 5), () => _startStateMachine(service));
  }, onError: (err) {
    _log(service, 'WebSocket error: $err');
    Future.delayed(const Duration(seconds: 5), () => _startStateMachine(service));
  });

  // Kickstart the machine
  if (routePoints.isNotEmpty) {
    transitionTo(EngineState.Jumping);
    triggerStateLogic();
  } else {
    transitionTo(EngineState.Idle);
  }
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
    return; // Zygarde Offline
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
      initialNotificationContent: 'Monitoring state...',
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
