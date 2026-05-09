import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'package:google_fonts/google_fonts.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final routes = await RouteDatabase.instance.getAllRoutes();
    setState(() {
      _savedRoutes = routes;
    });
  }

  Future<void> _processGpx() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );

    if (result == null || result.files.single.path == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Parsing GPX...';
    });

    try {
      File file = File(result.files.single.path!);
      String xmlString = await file.readAsString();
      final document = XmlDocument.parse(xmlString);

      // Extract all points (trkpt or wpt)
      List<LatLng> allPoints = [];
      final pts = document.findAllElements('trkpt').toList();
      pts.addAll(document.findAllElements('wpt'));

      for (var pt in pts) {
        final latStr = pt.getAttribute('lat');
        final lonStr = pt.getAttribute('lon');
        if (latStr != null && lonStr != null) {
          allPoints.add(LatLng(double.parse(latStr), double.parse(lonStr)));
        }
      }

      if (allPoints.isEmpty) {
        setState(() {
          _statusMessage = 'No points found in GPX.';
          _isProcessing = false;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Decimating points...';
      });

      // strict path adherence: EXACTLY 173.2 meters apart
      final Distance distanceObj = const Distance();
      List<Map<String, dynamic>> hexPoints = [];
      LatLng currentPos = allPoints.first;

      // add first point
      hexPoints.add({
        'lat': currentPos.latitude,
        'lng': currentPos.longitude,
        'cooldown': 0.0,
      });

      double requiredDistance = 173.2;
      double currentSegmentAccumulation = 0.0;

      for (int i = 1; i < allPoints.length; i++) {
        LatLng p1 = currentPos;
        LatLng p2 = allPoints[i];
        
        double segmentLength = distanceObj.as(LengthUnit.Meter, p1, p2);
        
        while (currentSegmentAccumulation + segmentLength >= requiredDistance) {
          double remainingNeeded = requiredDistance - currentSegmentAccumulation;
          double fraction = remainingNeeded / segmentLength;
          
          // Interpolate
          double newLat = p1.latitude + (p2.latitude - p1.latitude) * fraction;
          double newLng = p1.longitude + (p2.longitude - p1.longitude) * fraction;
          LatLng newPos = LatLng(newLat, newLng);
          
          double distReal = distanceObj.as(LengthUnit.Meter, hexPoints.last['lat'] != null ? LatLng(hexPoints.last['lat'], hexPoints.last['lng']) : newPos, newPos);
          double cooldown = (distReal / 2.91) + 2.0;

          hexPoints.add({
            'lat': newPos.latitude,
            'lng': newPos.longitude,
            'cooldown': cooldown,
          });

          // Move p1 to the newly generated point
          p1 = newPos;
          segmentLength = distanceObj.as(LengthUnit.Meter, p1, p2);
          currentSegmentAccumulation = 0;
        }
        currentSegmentAccumulation += segmentLength;
        currentPos = p2;
      }

      // Save to SQLite
      String routeName = result.files.single.name;
      await RouteDatabase.instance.insertRoute(routeName, hexPoints.length, hexPoints);

      setState(() {
        _statusMessage = 'Decimation complete! Generated \${hexPoints.length} points.';
        _isProcessing = false;
      });

      _loadRoutes();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: \$e';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 80.0, left: 20, right: 20, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 8),
            Text(
              'GPX to Hex Decimator (173.2m strict)',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 30),
            
            // Upload button
            GestureDetector(
              onTap: _isProcessing ? null : _processGpx,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: SovereignTheme.accentGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: SovereignTheme.accentViolet.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _isProcessing 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        'UPLOAD .GPX',
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            Center(
              child: Text(
                _statusMessage,
                style: GoogleFonts.inter(color: SovereignTheme.accentViolet, fontSize: 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: SovereignTheme.accentViolet.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.route_rounded, color: SovereignTheme.accentViolet, size: 20),
                            ),
                            title: Text(route['name'], style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                            subtitle: Text('\${route['pointCount']} Hex Points', style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
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
