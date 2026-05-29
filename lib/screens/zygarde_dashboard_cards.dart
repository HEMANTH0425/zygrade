import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/zygarde_config.dart';
import '../theme/sovereign_theme.dart';

class CatchingCard extends StatelessWidget {
  final ZygardeConfig config;
  final Function(ZygardeConfig) onChanged;

  const CatchingCard({super.key, required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'CATCHING',
      icon: Icons.catching_pokemon,
      children: [
        _Toggle('Auto Transfer', config.autoTransfer, (v) => onChanged(config..autoTransfer = v)),
        _Toggle('Quick Catch', config.quickCatch, (v) => onChanged(config..quickCatch = v)),
        _Toggle('Never Miss', config.neverMiss, (v) => onChanged(config..neverMiss = v)),
        _Toggle('Force Curve', config.forceCurve, (v) => onChanged(config..forceCurve = v)),
        _Toggle('AR+ Helper', config.arHelper, (v) => onChanged(config..arHelper = v)),
        _Toggle('Auto Feed Berry', config.autoFeedBerry, (v) => onChanged(config..autoFeedBerry = v)),
        _Toggle('Force Throw Type', config.forceThrowType, (v) => onChanged(config..forceThrowType = v)),
        _Toggle('Retry Throw', config.retryThrow, (v) => onChanged(config..retryThrow = v)),
        _Toggle('Catch on Touch', config.catchOnTouch, (v) => onChanged(config..catchOnTouch = v)),
        _Toggle('Display Stats', config.displayStats, (v) => onChanged(config..displayStats = v)),
        _Dropdown('Throw Type', config.throwType, ['None', 'Nice', 'Great', 'Excellent'], (v) => onChanged(config..throwType = v)),
        _Dropdown('Berry Type', config.berryType, ['None', 'Razz', 'Nanab', 'Pinap', 'Golden'], (v) => onChanged(config..berryType = v)),
      ],
    );
  }
}

class BuddyCard extends StatelessWidget {
  final ZygardeConfig config;
  final Function(ZygardeConfig) onChanged;

  const BuddyCard({super.key, required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'BUDDY',
      icon: Icons.pets_rounded,
      children: [
        _Toggle('Feed', config.feed, (v) => onChanged(config..feed = v)),
        _Toggle('Pet', config.pet, (v) => onChanged(config..pet = v)),
        _Toggle('Open Gift', config.openGift, (v) => onChanged(config..openGift = v)),
        _Dropdown('Snapshots', config.snapshots, List.generate(6, (i) => '$i shots'), (v) => onChanged(config..snapshots = v)),
      ],
    );
  }
}

class AutomationCard extends StatelessWidget {
  final ZygardeConfig config;
  final Function(ZygardeConfig) onChanged;

  const AutomationCard({super.key, required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'AUTOMATION',
      icon: Icons.smart_toy_rounded,
      children: [
        _Toggle('Auto Catch All', config.autoCatchAll, (v) => onChanged(config..autoCatchAll = v)),
        _Toggle('Auto Spin Stops', config.autoSpinPokestops, (v) => onChanged(config..autoSpinPokestops = v)),
        _Toggle('Auto Spin Gyms', config.autoSpinGyms, (v) => onChanged(config..autoSpinGyms = v)),
        _Toggle('Auto Gym Battle', config.autoGymBattle, (v) => onChanged(config..autoGymBattle = v)),
        _Toggle('Auto Encounter 100%', config.autoEncounter100, (v) => onChanged(config..autoEncounter100 = v)),
        _Toggle('Auto Encounter Shiny', config.autoEncounterShiny, (v) => onChanged(config..autoEncounterShiny = v)),
        _Toggle('Auto Encounter XXL', config.autoEncounterXXL, (v) => onChanged(config..autoEncounterXXL = v)),
        _Toggle('Scan Pokemon', config.scanPokemon, (v) => onChanged(config..scanPokemon = v)),
        _Toggle('Spawn Boost', config.spawnBoost, (v) => onChanged(config..spawnBoost = v)),
        _Toggle('Skip Cutscenes', config.skipCutscenes, (v) => onChanged(config..skipCutscenes = v)),
      ],
    );
  }
}

class VisualsCard extends StatelessWidget {
  final ZygardeConfig config;
  final Function(ZygardeConfig) onChanged;

  const VisualsCard({super.key, required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'VISUALS',
      icon: Icons.remove_red_eye_rounded,
      children: [
        _Toggle('Snow Effect', config.snow, (v) => onChanged(config..snow = v)),
        _Toggle('Weird Palette', config.weirdPalette, (v) => onChanged(config..weirdPalette = v)),
        _Dropdown('Pokestop Size', config.pokestopSize, List.generate(10, (i) => 'Size $i'), (v) => onChanged(config..pokestopSize = v)),
        _Dropdown('Gym Size', config.gymSize, List.generate(10, (i) => 'Size $i'), (v) => onChanged(config..gymSize = v)),
        _Dropdown('Station Size', config.stationSize, List.generate(10, (i) => 'Size $i'), (v) => onChanged(config..stationSize = v)),
        _Dropdown('Avatar Size', config.avatarSize, List.generate(10, (i) => 'Size $i'), (v) => onChanged(config..avatarSize = v)),
      ],
    );
  }
}

class PrivacyCard extends StatelessWidget {
  final ZygardeConfig config;
  final Function(ZygardeConfig) onChanged;

  const PrivacyCard({super.key, required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'PRIVACY',
      icon: Icons.lock_rounded,
      children: [
        _Toggle('Hide Name', config.hideName, (v) => onChanged(config..hideName = v)),
        _Toggle('Hide Level', config.hideLevel, (v) => onChanged(config..hideLevel = v)),
        _Toggle('Hide Other Info', config.hideOtherInfo, (v) => onChanged(config..hideOtherInfo = v)),
      ],
    );
  }
}

class TechnicalCard extends StatelessWidget {
  final ZygardeConfig config;
  final Function(ZygardeConfig) onChanged;

  const TechnicalCard({super.key, required this.config, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'TECHNICAL',
      icon: Icons.terminal_rounded,
      children: [
        _Toggle('Location Spoofing', config.locationSpoofing, (v) => onChanged(config..locationSpoofing = v)),
        _Toggle('Web Server', config.webServer, (v) => onChanged(config..webServer = v)),
        _Toggle('Seccomp Filters', config.seccompFilters, (v) => onChanged(config..seccompFilters = v)),
        _Toggle('Disable Quago', config.disableQuago, (v) => onChanged(config..disableQuago = v)),
        _Toggle('Fast Load', config.fastLoad, (v) => onChanged(config..fastLoad = v)),
        _Toggle("Don't load on next launch", config.dontLoadNextLaunch, (v) => onChanged(config..dontLoadNextLaunch = v)),
      ],
    );
  }
}


// ── Shared UI Components ──────────────────────────────────────────────────────

class _DashboardCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _DashboardCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: SovereignTheme.accentCyan, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: SovereignTheme.accentCyan,
            activeTrackColor: SovereignTheme.accentCyan.withOpacity(0.2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final int value;
  final List<String> options;
  final ValueChanged<int> onChanged;

  const _Dropdown(this.label, this.value, this.options, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButton<int>(
              value: value.clamp(0, options.length - 1),
              items: List.generate(options.length, (i) => DropdownMenuItem(
                value: i,
                child: Text(options[i], style: const TextStyle(color: Colors.white, fontSize: 12)),
              )),
              onChanged: (v) => v != null ? onChanged(v) : null,
              underline: const SizedBox(),
              dropdownColor: SovereignTheme.bgLayer,
              icon: const Icon(Icons.arrow_drop_down, color: SovereignTheme.accentCyan),
            ),
          ),
        ],
      ),
    );
  }
}
