import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../database/route_database.dart';
import '../theme/sovereign_theme.dart';

class RouteMasterScreen extends StatefulWidget {
  const RouteMasterScreen({super.key});

  @override
  State<RouteMasterScreen> createState() => _RouteMasterScreenState();
}

class _RouteMasterScreenState extends State<RouteMasterScreen> {
  List<Map<String, dynamic>> _savedRoutes = [];
  bool _isProcessing = false;
  String _statusMessage = 'Ready to Decimate GPX';
  int? _selectedRouteId;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
    _loadSelectedRoute();
  }

  Future<void> _loadSelectedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedRouteId = prefs.getInt('selected_route_id');
    });
  }

  Future<void> _onRouteSelected(int? id) async {
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_route_id', id);
    setState(() {
      _selectedRouteId = id;
    });
    
    // Notify background service
    FlutterBackgroundService().invoke('selectRoute', {'id': id});
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Active Route Updated'),
        backgroundColor: SovereignTheme.accentViolet,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _loadRoutes() async {
    final routes = await RouteDatabase.instance.getAllRoutes();
    setState(() {
      _savedRoutes = routes;
      // Ensure selection is valid
      if (_selectedRouteId != null && !routes.any((r) => r['id'] == _selectedRouteId)) {
        _selectedRouteId = null;
      }
    });
  }

  Future<void> _processGpx() async {
    debugPrint('Sovereign: _processGpx triggered');
    final docDir = await getApplicationDocumentsDirectory();
    final routesDir = Directory('${docDir.path}/Sovereign/Routes');
    
    if (!routesDir.existsSync()) {
      debugPrint('Sovereign: Creating routes directory: ${routesDir.path}');
      await routesDir.create(recursive: true);
    }
    
    debugPrint('Sovereign: Opening FilePicker (FileType.any)...');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) return;

    String path = result.files.single.path!;
    String ext = path.toLowerCase();
    
    // Manual extension check to avoid Android MIME type issues
    if (ext.endsWith('.db') || ext.endsWith('.sqlite')) {
      _importFromDb(initialPath: path);
      return;
    }

    if (!ext.endsWith('.gpx') && !ext.endsWith('.xml')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid file. Please select a .gpx or .xml file.')),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Parsing Hex Route...';
    });

    try {
      File file = File(path);
      String xmlString = await file.readAsString();
      final document = XmlDocument.parse(xmlString);

      List<LatLng> rawPoints = [];
      final trkpts = document.findAllElements('trkpt');
      final wpts   = document.findAllElements('wpt');
      final rtepts = document.findAllElements('rtept');

      for (var pt in [...trkpts, ...wpts, ...rtepts]) {
        String? latStr = pt.getAttribute('lat');
        String? lonStr = pt.getAttribute('lon') ?? pt.getAttribute('lng');
        
        // Fallback: check if they are child elements
        if (latStr == null) {
          final latElements = pt.findElements('lat');
          if (latElements.isNotEmpty) latStr = latElements.first.innerText;
        }
        if (lonStr == null) {
          final lonElements = pt.findElements('lon').isNotEmpty 
              ? pt.findElements('lon') 
              : pt.findElements('lng');
          if (lonElements.isNotEmpty) lonStr = lonElements.first.innerText;
        }

        if (latStr != null && lonStr != null) {
          final lat = double.tryParse(latStr);
          final lon = double.tryParse(lonStr);
          if (lat != null && lon != null) {
            rawPoints.add(LatLng(lat, lon));
          }
        }
      }

      if (rawPoints.isEmpty) throw 'No coordinates found in file.';

      setState(() => _statusMessage = 'Applying 173.2m Hex Decimator...');

      final Distance distanceObj = const Distance();
      List<Map<String, dynamic>> optimizedRoute = [];
      
      // 1. Initialize with the first point
      LatLng lastSavedPoint = rawPoints.first;
      optimizedRoute.add({
        'lat': lastSavedPoint.latitude,
        'lng': lastSavedPoint.longitude,
        'cooldown': 0.0,
      });

      // 2. Loop and Decimate
      const double kHexThreshold = 173.2; // The Golden Hex-Sweep Distance

      for (int i = 1; i < rawPoints.length; i++) {
        LatLng currentPoint = rawPoints[i];
        double dist = distanceObj.as(LengthUnit.Meter, lastSavedPoint, currentPoint);

        // 3. ONLY save if we have cleared the 173.2m threshold
        if (dist >= kHexThreshold) {
          // Cooldown math: (dist / 2.91 m/s) + 2s buffer
          double cooldown = (dist / 2.91) + 2.0;

          optimizedRoute.add({
            'lat': currentPoint.latitude,
            'lng': currentPoint.longitude,
            'cooldown': cooldown,
          });
          
          lastSavedPoint = currentPoint;
        }
      }

      String routeName = result.files.single.name;
      await RouteDatabase.instance.insertRoute(routeName, optimizedRoute.length, optimizedRoute);

      setState(() {
        _statusMessage = 'Optimization Complete: ${optimizedRoute.length} Hex Points.';
        _isProcessing = false;
      });

      _loadRoutes();
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _importFromDb({String? initialPath}) async {
    debugPrint('Sovereign: _importFromDb called (initialPath: $initialPath)');
    setState(() => _isProcessing = true);
    
    try {
      String? path = initialPath;
      
      if (path == null) {
        debugPrint('Sovereign: Requesting FilePicker.any for DB...');
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );

        if (result == null || result.files.single.path == null) {
          setState(() => _statusMessage = 'Import Cancelled');
          return;
        }
        path = result.files.single.path!;
      }

      debugPrint('Sovereign: Processing DB Path: $path');
      
      setState(() => _statusMessage = 'Buffering DB to cache...');
      final tempDir = await getTemporaryDirectory();
      final localDbPath = "${tempDir.path}/temp_import.db";
      final localFile = File(localDbPath);
      
      if (localFile.existsSync()) await localFile.delete();
      await File(path).copy(localDbPath);

      final bytes = await localFile.readAsBytes();
      if (bytes.length < 32) throw 'File is too small to be a database.';

      final header = String.fromCharCodes(bytes.sublist(0, 15));
      
      // Byte comparison for 'T-DB' (84, 45, 68, 66)
      bool isTDB = false;
      List<int> tagBytes = [];
      if (bytes.length > 20) {
        tagBytes = bytes.sublist(16, 20);
        if (tagBytes[0] == 84 && tagBytes[1] == 45 && tagBytes[2] == 68 && tagBytes[3] == 66) {
          isTDB = true;
        }
      }

      debugPrint('Sovereign: Header="$header", isTDB=$isTDB, TagBytes=$tagBytes');

      if (header == 'SQLite format 3') {
        debugPrint('Sovereign: Standard SQLite detected.');
        setState(() => _statusMessage = 'Parsing SQLite Tables...');
        final Database externalDb = await openDatabase(localDbPath, readOnly: true);

        final List<Map<String, dynamic>> tables = await externalDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        );

        int count = 0;
        for (var tableInfo in tables) {
          String tableName = tableInfo['name'];
          final List<Map<String, dynamic>> rows = await externalDb.query(tableName);
          if (rows.isEmpty) continue;

          String? latCol, lonCol;
          final columns = rows.first.keys.toList();
          for (var col in columns) {
            String c = col.toLowerCase();
            if (c == 'lat' || c == 'latitude' || c == 'x') latCol = col;
            if (c == 'lon' || c == 'lng' || c == 'longitude' || c == 'y') lonCol = col;
          }

          if (latCol != null && lonCol != null) {
            List<LatLng> points = [];
            for (var row in rows) {
              try {
                double lat = double.parse(row[latCol].toString());
                double lon = double.parse(row[lonCol].toString());
                points.add(LatLng(lat, lon));
              } catch (_) {}
            }
            if (points.isNotEmpty) {
              await _processAndSaveRoute("DB: $tableName", points);
              count++;
            }
          }
        }
        await externalDb.close();
        setState(() => _statusMessage = 'Imported $count routes from SQLite.');
      } else if (isTDB) {
        debugPrint('Sovereign: Proprietary T-DB Detected. Harvesting...');
        
        int latPtr = 0x280;
        int lngPtr = 0x23E68;
        int metaOff = 0x80180;
        
        final metadataStr = String.fromCharCodes(bytes.sublist(0x80000));
        final namePattern = RegExp(r'[A-Za-z0-9 _-]{4,}');
        final nameMatches = namePattern.allMatches(metadataStr)
            .map((m) => m.group(0)!)
            .where((n) => !n.startsWith('class_') && n.length > 3)
            .toList();

        // 1. Extract Clean Names from the 0x80BD0 metadata block
        final List<String> cleanNames = [];
        const int nameOffset = 0x80BD0;
        if (bytes.length > nameOffset) {
          final metaBytes = bytes.sublist(nameOffset, (nameOffset + 4096).clamp(0, bytes.length));
          final rawStrings = String.fromCharCodes(metaBytes).split(RegExp(r'[\x00\x01]'));
          for (var s in rawStrings) {
            final trimmed = s.trim();
            // GPS Joystick numbered format: "01 - Name"
            if (RegExp(r'^\d{2}\s*-\s*').hasMatch(trimmed)) {
              cleanNames.add(trimmed);
            }
          }
        }
        debugPrint('Sovereign: Extracted ${cleanNames.length} numbered names.');

        // 2. Map all AAAA blocks and Classify by Range
        List<Map<String, dynamic>> latBlocks = [];
        List<Map<String, dynamic>> lngBlocks = [];

        final bd = ByteData.view(bytes.buffer);
        for (int i = 0; i < bytes.length - 16; i++) {
          if (bytes[i] == 0x41 && bytes[i+1] == 0x41 && bytes[i+2] == 0x41 && bytes[i+3] == 0x41) {
            int count = (bytes[i+6] << 8) | bytes[i+7]; // Big-endian count
            if (count >= 5 && count < 50000) {
              double firstVal = bd.getFloat64(i + 8, Endian.little);
              
              // Forensic Range Check:
              // Latitudes are ALWAYS between -90 and 90.
              // We'll peek a few values to be sure.
              bool isLat = firstVal.abs() <= 90 && firstVal != 0;
              
              final block = {
                'offset': i + 8,
                'count': count,
              };

              if (isLat) {
                latBlocks.add(block);
              } else {
                lngBlocks.add(block);
              }
              i += 7; // Skip tag
            }
          }
        }

        debugPrint('Sovereign: Found ${latBlocks.length} Lat blocks and ${lngBlocks.length} Lng blocks.');

        // 3. Pair and Build Routes
        int harvested = 0;
        int limit = latBlocks.length < lngBlocks.length ? latBlocks.length : lngBlocks.length;
        
        for (int i = 0; i < limit; i++) {
          final lB = latBlocks[i];
          final nB = lngBlocks[i];
          
          int ptCount = lB['count'];
          int latPtr = lB['offset'];
          int lngPtr = nB['offset'];
          
          List<LatLng> points = [];
          for (int p = 0; p < ptCount; p++) {
            if (latPtr + 8 > bytes.length || lngPtr + 8 > bytes.length) break;
            double lat = bd.getFloat64(latPtr, Endian.little);
            double lng = bd.getFloat64(lngPtr, Endian.little);
            
            if (lat.abs() <= 90 && lng.abs() <= 180 && (lat != 0 || lng != 0)) {
              points.add(LatLng(lat, lng));
            }
            latPtr += 8;
            lngPtr += 8;
          }
          
          if (points.length >= 5) {
            String name = (harvested < cleanNames.length) ? cleanNames[harvested] : "Route ${harvested + 1}";
            await _processAndSaveRoute(name, points);
            harvested++;
          }
        }

        setState(() {
          _statusMessage = 'Successfully Converted $harvested Master Routes.';
        });
      } else {
        throw 'Unsupported format. (Hdr: ${header.substring(0, 8)})';
      }
    } catch (e) {
      debugPrint('Sovereign: Conversion Error: $e');
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      setState(() => _isProcessing = false);
      await _loadRoutes();
    }
  }

  Future<void> _processAndSaveRoute(String name, List<LatLng> allPoints) async {
    final Distance distanceObj = const Distance();
    List<Map<String, dynamic>> optimizedRoute = [];
    
    LatLng lastSavedPoint = allPoints.first;
    optimizedRoute.add({
      'lat': lastSavedPoint.latitude,
      'lng': lastSavedPoint.longitude,
      'cooldown': 0.0,
    });

    const double kHexThreshold = 173.2;

    for (int i = 1; i < allPoints.length; i++) {
      LatLng currentPoint = allPoints[i];
      double dist = distanceObj.as(LengthUnit.Meter, lastSavedPoint, currentPoint);

      if (dist >= kHexThreshold) {
        double cooldown = (dist / 2.91) + 2.0;

        optimizedRoute.add({
          'lat': currentPoint.latitude,
          'lng': currentPoint.longitude,
          'cooldown': cooldown,
        });
        
        lastSavedPoint = currentPoint;
      }
    }

    await RouteDatabase.instance.insertRoute(name, optimizedRoute.length, optimizedRoute);
  }

  void _log(String msg) {
    debugPrint('RouteMaster: $msg');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROUTE MASTER',
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Smart Path Converter (Safe Cooldowns)',
                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'GHOST',
                      style: GoogleFonts.rajdhani(
                        color: SovereignTheme.accentCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: true,
                        onChanged: (v) {},
                        activeColor: SovereignTheme.accentCyan,
                        activeTrackColor: SovereignTheme.accentCyan.withOpacity(0.2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Active Route Dropdown
            Text(
              'ACTIVE ROUTE SELECTION',
              style: GoogleFonts.rajdhani(
                color: SovereignTheme.accentCyan,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: SovereignTheme.glassWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SovereignTheme.glassBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedRouteId,
                  hint: Text('Select a route to follow', style: GoogleFonts.inter(color: Colors.white30, fontSize: 14)),
                  dropdownColor: const Color(0xFF1A1A2E),
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: SovereignTheme.accentCyan),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  items: _savedRoutes.map((route) {
                    return DropdownMenuItem<int>(
                      value: route['id'],
                      child: Text(route['name']),
                    );
                  }).toList(),
                  onChanged: _onRouteSelected,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Status Message Display
            if (_statusMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('Error') 
                      ? SovereignTheme.danger.withOpacity(0.1)
                      : SovereignTheme.accentCyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage.contains('Error') 
                        ? SovereignTheme.danger.withOpacity(0.3)
                        : SovereignTheme.accentCyan.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusMessage.contains('Error') ? Icons.error_outline : Icons.info_outline,
                      color: _statusMessage.contains('Error') ? SovereignTheme.danger : SovereignTheme.accentCyan,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(
                  backgroundColor: SovereignTheme.glassWhite,
                  valueColor: AlwaysStoppedAnimation<Color>(SovereignTheme.accentCyan),
                ),
              ),
            
            // Upload button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isProcessing ? null : _processGpx,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    gradient: SovereignTheme.accentGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: SovereignTheme.accentViolet.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.file_upload_outlined, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        'COMPILE GPX ROUTE',
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // DB Collection Button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isProcessing ? null : _importFromDb,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: SovereignTheme.glassWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SovereignTheme.glassBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.storage_rounded, color: SovereignTheme.accentCyan),
                      const SizedBox(width: 12),
                      Text(
                        'IMPORT .DB COLLECTION',
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            Text(
              'SAVED HEX ROUTES',
              style: GoogleFonts.rajdhani(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            
            Expanded(
              child: _savedRoutes.isEmpty
                  ? Center(child: Text('No routes generated yet.', style: GoogleFonts.inter(color: Colors.white30)))
                  : ListView.builder(
                      itemCount: _savedRoutes.length,
                      itemBuilder: (context, index) {
                        final route = _savedRoutes[index];
                        final isSelected = route['id'] == _selectedRouteId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? SovereignTheme.accentViolet.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? SovereignTheme.accentCyan : Colors.white.withOpacity(0.1),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            onTap: () => _onRouteSelected(route['id']),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isSelected ? SovereignTheme.accentCyan : SovereignTheme.accentViolet).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.route_rounded,
                                color: isSelected ? SovereignTheme.accentCyan : SovereignTheme.accentViolet,
                                size: 20,
                              ),
                            ),
                            title: Text(route['name'], style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                            subtitle: Text("${route['pointCount']} Hex Points", style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white38),
                              onPressed: () async {
                                await RouteDatabase.instance.deleteRoute(route['id']);
                                _loadRoutes();
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
