# Sovereign Mobile 📱

> Dark glassmorphic Flutter Android app — Zygarde WebUI client + Smart Bag Manager daemon.

---

## Project Structure

```
lib/
├── main.dart                     ← App entry, tab shell, background service init
├── theme/sovereign_theme.dart    ← Glassmorphic dark theme + reusable widgets
├── screens/
│   ├── webview_screen.dart       ← Tab 1: Zygarde WebView
│   └── bag_logic_screen.dart     ← Tab 2: Smart Bag Logic Dashboard
└── services/
    └── bag_service.dart          ← Android foreground service (Dart port of bagmanager.py)
```

---

## Build Instructions

### Prerequisites
- Flutter SDK ≥ 3.19 ([flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install))
- Android Studio / Android SDK (API 21+)
- Java 17 (bundled with Android Studio)

### Steps

```bash
# 1. Navigate to the project
cd sovereign_mobile

# 2. Install dependencies
flutter pub get

# 3. Run on connected device / emulator
flutter run

# 4. Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Configuration

### Zygarde Server URL
- **On-device (default):** `http://localhost:8080` — if Zygarde runs on the phone itself.
- **LAN (PC server):** Tap the ✏️ edit icon in the Bag Logic header and enter `http://192.168.x.x:8080`.

### Bag Limits
Open **Tab 2 → Bag Logic**:
1. Type a keep-limit next to each item (e.g. `100` for Ultra Balls, `0` for Nanab Berries).
2. Tap **SAVE & APPLY** — limits are written to `SharedPreferences` and pushed to the daemon instantly.
3. The daemon runs automatically every **60 seconds** in the background.

---

## Background Service Logic (bagmanager.py → Dart)

| Python | Dart Equivalent |
|--------|-----------------|
| `load_config(farming.txt)` | `SharedPreferences.getString('keep_limits_json')` |
| `requests.get(INVENTORY_API)` | `http.get(Uri.parse('$baseUrl/api/item/all'))` |
| `websocket.create_connection(WS_URL)` | `WebSocket.connect(wsUrl)` |
| `ws.send(json.dumps(payload))` | `ws.add(jsonEncode(payload))` |
| `time.sleep(CHECK_INTERVAL)` | `Timer.periodic(Duration(seconds: 60), ...)` |

---

## WebSocket Payload (unchanged from bagmanager.py)

```json
{
  "type": "action",
  "action": "item.recycle",
  "requestId": "<timestamp>",
  "payload": {
    "itemId": 3,
    "amount": 150
  }
}
```

---

## Emulator Note

On the Android Emulator, `localhost` maps to the emulator itself, not your PC.  
Use `http://10.0.2.2:8080` to reach a server on your host machine.
