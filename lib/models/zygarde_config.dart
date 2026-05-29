import 'dart:convert';

class ZygardeConfig {
  // General / Catching
  bool autoTransfer;
  bool nicknamePokemon;
  bool feed;
  bool pet;
  bool openGift;
  int snapshots; // 0-5
  bool quickCatch;
  bool neverMiss;
  bool forceCurve;
  bool arHelper;
  bool autoFeedBerry;
  bool forceThrowType;
  bool retryThrow;
  bool autoEncounter100;
  bool autoEncounterShiny;
  bool autoEncounterXXL;
  bool catchOnTouch;
  bool displayStats;
  int berryType; // 0-4
  int throwType; // 0-3 (None, Nice, Great, Excellent)
  bool skipCutscenes;
  bool dontLoadNextLaunch;
  bool seccompFilters;
  bool sendToWebhook;
  String webhookUrl;

  // Visuals
  bool snow;
  bool weirdPalette;
  int pokestopSize; // 0-9
  int gymSize; // 0-9
  int stationSize; // 0-9
  int avatarSize; // 0-9
  bool hideName;
  bool hideLevel;
  bool hideOtherInfo;
  String customName;

  // Automation / Technical
  bool autoGymBattle;
  bool scanPokemon;
  bool spawnBoost;
  bool spawnBoostAlt;
  bool autoCatchAll;
  bool fastLoad;
  bool disableQuago;
  bool tapToSpinPokestops;
  bool tapToSpinGyms;
  bool autoSpinPokestops;
  bool autoSpinGyms;
  bool locationSpoofing;
  bool webServer;
  String stadiaMapsKey;
  int recycleAmount;

  ZygardeConfig({
    this.autoTransfer = true,
    this.nicknamePokemon = true,
    this.feed = true,
    this.pet = true,
    this.openGift = false,
    this.snapshots = 4,
    this.quickCatch = true,
    this.neverMiss = true,
    this.forceCurve = true,
    this.arHelper = true,
    this.autoFeedBerry = true,
    this.forceThrowType = true,
    this.retryThrow = true,
    this.autoEncounter100 = false,
    this.autoEncounterShiny = false,
    this.autoEncounterXXL = false,
    this.catchOnTouch = false,
    this.displayStats = true,
    this.berryType = 0,
    this.throwType = 2, // Great
    this.skipCutscenes = true,
    this.dontLoadNextLaunch = false,
    this.seccompFilters = true,
    this.sendToWebhook = true,
    this.webhookUrl = "",
    this.snow = false,
    this.weirdPalette = false,
    this.pokestopSize = 0,
    this.gymSize = 0,
    this.stationSize = 0,
    this.avatarSize = 0,
    this.hideName = true,
    this.hideLevel = false,
    this.hideOtherInfo = false,
    this.customName = "",
    this.autoGymBattle = true,
    this.scanPokemon = true,
    this.spawnBoost = true,
    this.spawnBoostAlt = true,
    this.autoCatchAll = true,
    this.fastLoad = true,
    this.disableQuago = false,
    this.tapToSpinPokestops = false,
    this.tapToSpinGyms = false,
    this.autoSpinPokestops = true,
    this.autoSpinGyms = true,
    this.locationSpoofing = false,
    this.webServer = true,
    this.stadiaMapsKey = "",
    this.recycleAmount = 1,
  });

  Map<String, dynamic> toJson() => {
    'autoTransfer': autoTransfer,
    'nicknamePokemon': nicknamePokemon,
    'feed': feed,
    'pet': pet,
    'openGift': openGift,
    'snapshots': snapshots,
    'quickCatch': quickCatch,
    'neverMiss': neverMiss,
    'forceCurve': forceCurve,
    'arHelper': arHelper,
    'autoFeedBerry': autoFeedBerry,
    'forceThrowType': forceThrowType,
    'retryThrow': retryThrow,
    'autoEncounter100': autoEncounter100,
    'autoEncounterShiny': autoEncounterShiny,
    'autoEncounterXXL': autoEncounterXXL,
    'catchOnTouch': catchOnTouch,
    'displayStats': displayStats,
    'berryType': berryType,
    'throwType': throwType,
    'skipCutscenes': skipCutscenes,
    'dontLoadNextLaunch': dontLoadNextLaunch,
    'seccompFilters': seccompFilters,
    'sendToWebhook': sendToWebhook,
    'webhookUrl': webhookUrl,
    'snow': snow,
    'weirdPalette': weirdPalette,
    'pokestopSize': pokestopSize,
    'gymSize': gymSize,
    'stationSize': stationSize,
    'avatarSize': avatarSize,
    'hideName': hideName,
    'hideLevel': hideLevel,
    'hideOtherInfo': hideOtherInfo,
    'customName': customName,
    'autoGymBattle': autoGymBattle,
    'scanPokemon': scanPokemon,
    'spawnBoost': spawnBoost,
    'spawnBoostAlt': spawnBoostAlt,
    'autoCatchAll': autoCatchAll,
    'fastLoad': fastLoad,
    'disableQuago': disableQuago,
    'tapToSpinPokestops': tapToSpinPokestops,
    'tapToSpinGyms': tapToSpinGyms,
    'autoSpinPokestops': autoSpinPokestops,
    'autoSpinGyms': autoSpinGyms,
    'locationSpoofing': locationSpoofing,
    'webServer': webServer,
    'stadiaMapsKey': stadiaMapsKey,
    'recycleAmount': recycleAmount,
  };

  factory ZygardeConfig.fromJson(Map<String, dynamic> json) => ZygardeConfig(
    autoTransfer: json['autoTransfer'] ?? true,
    nicknamePokemon: json['nicknamePokemon'] ?? true,
    feed: json['feed'] ?? true,
    pet: json['pet'] ?? true,
    openGift: json['openGift'] ?? false,
    snapshots: json['snapshots'] ?? 4,
    quickCatch: json['quickCatch'] ?? true,
    neverMiss: json['neverMiss'] ?? true,
    forceCurve: json['forceCurve'] ?? true,
    arHelper: json['arHelper'] ?? true,
    autoFeedBerry: json['autoFeedBerry'] ?? true,
    forceThrowType: json['forceThrowType'] ?? true,
    retryThrow: json['retryThrow'] ?? true,
    autoEncounter100: json['autoEncounter100'] ?? false,
    autoEncounterShiny: json['autoEncounterShiny'] ?? false,
    autoEncounterXXL: json['autoEncounterXXL'] ?? false,
    catchOnTouch: json['catchOnTouch'] ?? false,
    displayStats: json['displayStats'] ?? true,
    berryType: json['berryType'] ?? 0,
    throwType: json['throwType'] ?? 2,
    skipCutscenes: json['skipCutscenes'] ?? true,
    dontLoadNextLaunch: json['dontLoadNextLaunch'] ?? false,
    seccompFilters: json['seccompFilters'] ?? true,
    sendToWebhook: json['sendToWebhook'] ?? true,
    webhookUrl: json['webhookUrl'] ?? "",
    snow: json['snow'] ?? false,
    weirdPalette: json['weirdPalette'] ?? false,
    pokestopSize: json['pokestopSize'] ?? 0,
    gymSize: json['gymSize'] ?? 0,
    stationSize: json['stationSize'] ?? 0,
    avatarSize: json['avatarSize'] ?? 0,
    hideName: json['hideName'] ?? true,
    hideLevel: json['hideLevel'] ?? false,
    hideOtherInfo: json['hideOtherInfo'] ?? false,
    customName: json['customName'] ?? "",
    autoGymBattle: json['autoGymBattle'] ?? true,
    scanPokemon: json['scanPokemon'] ?? true,
    spawnBoost: json['spawnBoost'] ?? true,
    spawnBoostAlt: json['spawnBoostAlt'] ?? true,
    autoCatchAll: json['autoCatchAll'] ?? true,
    fastLoad: json['fastLoad'] ?? true,
    disableQuago: json['disableQuago'] ?? false,
    tapToSpinPokestops: json['tapToSpinPokestops'] ?? false,
    tapToSpinGyms: json['tapToSpinGyms'] ?? false,
    autoSpinPokestops: json['autoSpinPokestops'] ?? true,
    autoSpinGyms: json['autoSpinGyms'] ?? true,
    locationSpoofing: json['locationSpoofing'] ?? false,
    webServer: json['webServer'] ?? true,
    stadiaMapsKey: json['stadiaMapsKey'] ?? "",
    recycleAmount: json['recycleAmount'] ?? 1,
  );

  /// Generates JavaScript to inject into the Zygarde WebUI using the internal pushSetting protocol
  String toJSInjection() {
    final List<Map<String, dynamic>> updates = [
      {"cat": "Bag manager", "name": "Auto transfer", "type": "bool", "val": autoTransfer},
      {"cat": "Bag manager", "name": "Nickname pokemon", "type": "bool", "val": nicknamePokemon},
      {"cat": "Buddy", "name": "Feed", "type": "bool", "val": feed},
      {"cat": "Buddy", "name": "Pet", "type": "bool", "val": pet},
      {"cat": "Buddy", "name": "Open gift", "type": "bool", "val": openGift},
      {"cat": "Buddy", "name": "Snapshots", "type": "combo", "val": snapshots},
      {"cat": "Catch Assist", "name": "Quick catch", "type": "bool", "val": quickCatch},
      {"cat": "Catch Assist", "name": "Never miss", "type": "bool", "val": neverMiss},
      {"cat": "Catch Assist", "name": "Force curve", "type": "bool", "val": forceCurve},
      {"cat": "Catch Assist", "name": "AR+ helper", "type": "bool", "val": arHelper},
      {"cat": "Catch Assist", "name": "Auto feed berry", "type": "bool", "val": autoFeedBerry},
      {"cat": "Catch Assist", "name": "Force throw type", "type": "bool", "val": forceThrowType},
      {"cat": "Catch Assist", "name": "Retry throw", "type": "bool", "val": retryThrow},
      {"cat": "Catch Assist", "name": "Auto encounter 100%", "type": "bool", "val": autoEncounter100},
      {"cat": "Catch Assist", "name": "Auto encounter shiny", "type": "bool", "val": autoEncounterShiny},
      {"cat": "Catch Assist", "name": "Auto encounter XXL", "type": "bool", "val": autoEncounterXXL},
      {"cat": "Catch Assist", "name": "Catch on touch", "type": "bool", "val": catchOnTouch},
      {"cat": "Catch Assist", "name": "Display stats", "type": "bool", "val": displayStats},
      {"cat": "Catch Assist", "name": "Berry type", "type": "combo", "val": berryType},
      {"cat": "Catch Assist", "name": "Throw type", "type": "combo", "val": throwType},
      {"cat": "Cutscenes", "name": "Skip cutscenes", "type": "bool", "val": skipCutscenes},
      {"cat": "Debug", "name": "Don't load on next launch", "type": "bool", "val": dontLoadNextLaunch},
      {"cat": "Debug", "name": "seccomp filters", "type": "bool", "val": seccompFilters},
      {"cat": "Dump", "name": "Send to Webhook", "type": "bool", "val": sendToWebhook},
      {"cat": "Dump", "name": "Webhook", "type": "text", "val": webhookUrl},
      {"cat": "Fun", "name": "Snow", "type": "bool", "val": snow},
      {"cat": "Fun", "name": "Weird palette", "type": "bool", "val": weirdPalette},
      {"cat": "Fun", "name": "Pokestop size", "type": "combo", "val": pokestopSize},
      {"cat": "Fun", "name": "Gym size", "type": "combo", "val": gymSize},
      {"cat": "Fun", "name": "Station size", "type": "combo", "val": stationSize},
      {"cat": "Fun", "name": "Avatar size", "type": "combo", "val": avatarSize},
      {"cat": "Gym", "name": "Auto gym battle", "type": "bool", "val": autoGymBattle},
      {"cat": "Map", "name": "Scan Pokemon", "type": "bool", "val": scanPokemon},
      {"cat": "Map", "name": "Spawn boost", "type": "bool", "val": spawnBoost},
      {"cat": "Map", "name": "Spawn boost (alt)", "type": "bool", "val": spawnBoostAlt},
      {"cat": "Map", "name": "Auto catch all", "type": "bool", "val": autoCatchAll},
      {"cat": "Map", "name": "Fast load", "type": "bool", "val": fastLoad},
      {"cat": "NoTrack", "name": "Disable Quago", "type": "bool", "val": disableQuago},
      {"cat": "Pokestops", "name": "Tap to spin Pokestops", "type": "bool", "val": tapToSpinPokestops},
      {"cat": "Pokestops", "name": "Tap to spin Gyms", "type": "bool", "val": tapToSpinGyms},
      {"cat": "Pokestops", "name": "Auto spin Pokestops", "type": "bool", "val": autoSpinPokestops},
      {"cat": "Pokestops", "name": "Auto spin Gyms", "type": "bool", "val": autoSpinGyms},
      {"cat": "Privacy", "name": "Hide name", "type": "bool", "val": hideName},
      {"cat": "Privacy", "name": "Hide level", "type": "bool", "val": hideLevel},
      {"cat": "Privacy", "name": "Hide other info", "type": "bool", "val": hideOtherInfo},
      {"cat": "Privacy", "name": "Name", "type": "text", "val": customName},
      {"cat": "Spoofing", "name": "Location spoofing", "type": "bool", "val": locationSpoofing},
      {"cat": "Web UI", "name": "WebServer", "type": "bool", "val": webServer},
      {"cat": "Web UI", "name": "Stadia maps key", "type": "text", "val": stadiaMapsKey},
    ];

    final String jsonUpdates = jsonEncode(updates);

    return """
(async function() {
  const updates = $jsonUpdates;
  console.log('🦖 Sovereign IPC: Syncing ' + updates.length + ' settings...');
  
  if (typeof window.pushSetting !== 'function') {
    console.error('🦖 Sovereign IPC Error: pushSetting not found in WebUI');
    return 'pushSetting missing';
  }

  for (const item of updates) {
    try {
      await window.pushSetting({
        type: item.type,
        category: item.cat,
        name: item.name,
        value: item.val
      });
    } catch (e) {
      console.warn('🦖 IPC failed for ' + item.name + ': ' + e.message);
    }
  }
  
  if (typeof window.refreshSettings === 'function') {
    window.refreshSettings();
  }
  
  return 'Sync Complete';
})();
""";
  }
}
