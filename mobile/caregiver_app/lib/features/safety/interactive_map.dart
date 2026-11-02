import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A coordinate point representing latitude and longitude.
class MapCoordinate {
  final double latitude;
  final double longitude;

  const MapCoordinate(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapCoordinate &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Status of the patient relative to the safe-zone geofence.
enum GeofenceVisualState {
  inside,
  outside,
  uncertain,
  inactive,
}

/// Interactive Slippy Map widget rendered with OpenStreetMap tiles.
/// Supports panning, pinch-to-zoom, tap-to-select, geofence perimeter circle,
/// patient marker with accuracy halo, breadcrumb trail, and address search.
class MemoryGuideInteractiveMap extends StatefulWidget {
  final MapCoordinate initialCenter;
  final double initialZoom;
  final MapCoordinate? homeLocation;
  final double? safeZoneRadiusMeters;
  final MapCoordinate? patientLocation;
  final double? patientAccuracyMeters;
  final List<MapCoordinate> movementTrail;
  final GeofenceVisualState visualState;
  final bool isEditable;
  final ValueChanged<MapCoordinate>? onLocationSelected;
  final VoidCallback? onUseCurrentLocationRequested;

  const MemoryGuideInteractiveMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 16.0,
    this.homeLocation,
    this.safeZoneRadiusMeters,
    this.patientLocation,
    this.patientAccuracyMeters,
    this.movementTrail = const [],
    this.visualState = GeofenceVisualState.inactive,
    this.isEditable = false,
    this.onLocationSelected,
    this.onUseCurrentLocationRequested,
  });

  @override
  State<MemoryGuideInteractiveMap> createState() =>
      _MemoryGuideInteractiveMapState();
}

class _MemoryGuideInteractiveMapState extends State<MemoryGuideInteractiveMap> {
  late double _centerLat;
  late double _centerLon;
  late double _zoom;
  MapCoordinate? _selectedLocation;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _centerLat = widget.initialCenter.latitude;
    _centerLon = widget.initialCenter.longitude;
    _zoom = widget.initialZoom;
    _selectedLocation = widget.homeLocation;
  }

  @override
  void didUpdateWidget(covariant MemoryGuideInteractiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.homeLocation != oldWidget.homeLocation &&
        widget.homeLocation != null) {
      _selectedLocation = widget.homeLocation;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final scale = math.pow(2.0, _zoom).toDouble() * 256.0;
    // World pixels to lat/lon delta
    final dLon = -(details.delta.dx / scale) * 360.0;

    // Web mercator lat derivative approximation
    final latRad = _centerLat * math.pi / 180.0;
    final dLat = (details.delta.dy / scale) * 360.0 * math.cos(latRad);

    setState(() {
      _centerLon = (_centerLon + dLon).clamp(-180.0, 180.0);
      _centerLat = (_centerLat + dLat).clamp(-85.0511, 85.0511);
    });
  }

  void _zoomIn() {
    setState(() {
      _zoom = (_zoom + 0.5).clamp(10.0, 19.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - 0.5).clamp(10.0, 19.0);
    });
  }

  void _centerOn(double lat, double lon, [double? zoom]) {
    setState(() {
      _centerLat = lat;
      _centerLon = lon;
      if (zoom != null) _zoom = zoom;
    });
  }

  void _handleTapOnMap(TapUpDetails details, Size size) {
    if (!widget.isEditable) return;

    final clickX = details.localPosition.dx;
    final clickY = details.localPosition.dy;
    final centerX = size.width / 2.0;
    final centerY = size.height / 2.0;

    // Convert pixel offset from center to coordinate
    final dPixelX = clickX - centerX;
    final dPixelY = clickY - centerY;

    final centerWorld = _latLonToWorldPixels(_centerLat, _centerLon, _zoom);
    final targetWorldX = centerWorld.dx + dPixelX;
    final targetWorldY = centerWorld.dy + dPixelY;

    final targetCoord = _worldPixelsToLatLon(targetWorldX, targetWorldY, _zoom);
    final validLat = targetCoord.latitude.clamp(-90.0, 90.0);
    final validLon = targetCoord.longitude.clamp(-180.0, 180.0);

    final selected = MapCoordinate(validLat, validLon);
    setState(() {
      _selectedLocation = selected;
    });
    widget.onLocationSelected?.call(selected);
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'MemoryGuideCaregiver/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _searchResults = list.map((item) {
              return {
                'name': item['display_name'] ?? '',
                'lat': double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0,
                'lon': double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0,
              };
            }).toList();
            _isSearching = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // 1. Gesture detector for map panning & tapping
            GestureDetector(
              onPanUpdate: (details) => _onPanUpdate(details, size),
              onTapUp: (details) => _handleTapOnMap(details, size),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _OsmTileLayer(
                      centerLat: _centerLat,
                      centerLon: _centerLon,
                      zoom: _zoom,
                      size: size,
                    ),
                    CustomPaint(
                      size: size,
                      painter: _MapCanvasPainter(
                        centerLat: _centerLat,
                        centerLon: _centerLon,
                        zoom: _zoom,
                        homeLocation: widget.isEditable
                            ? _selectedLocation
                            : widget.homeLocation,
                        safeZoneRadiusMeters: widget.safeZoneRadiusMeters,
                        patientLocation: widget.patientLocation,
                        patientAccuracyMeters: widget.patientAccuracyMeters,
                        movementTrail: widget.movementTrail,
                        visualState: widget.visualState,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Search Bar overlay (if editable / search enabled)
            if (widget.isEditable)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search address or place...',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF174D43)),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF174D43),
                                    ),
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        onChanged: (text) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 500),
                            () => _searchAddress(text),
                          );
                        },
                      ),
                    ),
                    if (_searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: Color(0xFFE9EDE8)),
                          itemBuilder: (context, idx) {
                            final item = _searchResults[idx];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined,
                                  color: Color(0xFF174D43), size: 18),
                              title: Text(
                                item['name'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () {
                                final lat = item['lat'] as double;
                                final lon = item['lon'] as double;
                                final coord = MapCoordinate(lat, lon);
                                setState(() {
                                  _selectedLocation = coord;
                                  _centerLat = lat;
                                  _centerLon = lon;
                                  _zoom = 16.0;
                                  _searchResults = [];
                                  _searchController.text = item['name'];
                                });
                                widget.onLocationSelected?.call(coord);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

            // 3. Zoom Controls & Centering Buttons (Right side)
            Positioned(
              right: 12,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.homeLocation != null || _selectedLocation != null)
                    _MapActionButton(
                      tooltip: 'Center on Home Safe Zone',
                      icon: Icons.home_rounded,
                      color: const Color(0xFF174D43),
                      onPressed: () {
                        final target = widget.isEditable
                            ? _selectedLocation
                            : widget.homeLocation;
                        if (target != null) {
                          _centerOn(target.latitude, target.longitude, 16.0);
                        }
                      },
                    ),
                  if (widget.patientLocation != null) ...[
                    const SizedBox(height: 8),
                    _MapActionButton(
                      tooltip: 'Center on Patient Location',
                      icon: Icons.person_pin_circle_rounded,
                      color: const Color(0xFF2563EB),
                      onPressed: () {
                        if (widget.patientLocation != null) {
                          _centerOn(
                            widget.patientLocation!.latitude,
                            widget.patientLocation!.longitude,
                            17.0,
                          );
                        }
                      },
                    ),
                  ],
                  if (widget.onUseCurrentLocationRequested != null) ...[
                    const SizedBox(height: 8),
                    _MapActionButton(
                      tooltip: 'Use My Current GPS Position',
                      icon: Icons.my_location_rounded,
                      color: const Color(0xFF0F766E),
                      onPressed: widget.onUseCurrentLocationRequested!,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: 'Zoom In',
                          onPressed: _zoomIn,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 38, minHeight: 38),
                        ),
                        const Divider(height: 1, thickness: 1),
                        IconButton(
                          icon: const Icon(Icons.remove, size: 20),
                          tooltip: 'Zoom Out',
                          onPressed: _zoomOut,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 38, minHeight: 38),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 4. Attribution pill (Bottom left)
            Positioned(
              left: 10,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _MapActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Renders standard OpenStreetMap raster tiles underneath custom vector overlays.
class _OsmTileLayer extends StatelessWidget {
  final double centerLat;
  final double centerLon;
  final double zoom;
  final Size size;

  const _OsmTileLayer({
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();

    final z = zoom.floor().clamp(1, 19);
    final scaleRatio = math.pow(2.0, zoom - z).toDouble();
    final tileSize = 256.0 * scaleRatio;

    final centerWorld = _latLonToWorldPixels(centerLat, centerLon, zoom);
    final halfW = size.width / 2.0;
    final halfH = size.height / 2.0;

    final minTileX = ((centerWorld.dx - halfW) / tileSize).floor();
    final maxTileX = ((centerWorld.dx + halfW) / tileSize).floor();
    final minTileY = ((centerWorld.dy - halfH) / tileSize).floor();
    final maxTileY = ((centerWorld.dy + halfH) / tileSize).floor();

    final maxTileIndex = (1 << z) - 1;
    final List<Widget> tileWidgets = [];

    for (int ty = minTileY; ty <= maxTileY; ty++) {
      if (ty < 0 || ty > maxTileIndex) continue;
      for (int tx = minTileX; tx <= maxTileX; tx++) {
        final wrappedTx =
            ((tx % (maxTileIndex + 1)) + (maxTileIndex + 1)) % (maxTileIndex + 1);
        final left = halfW + (tx * tileSize - centerWorld.dx);
        final top = halfH + (ty * tileSize - centerWorld.dy);

        final url = 'https://tile.openstreetmap.org/$z/$wrappedTx/$ty.png';
        final fallbackUrl = 'https://basemaps.cartocdn.com/rastertiles/voyager/$z/$wrappedTx/$ty.png';

        tileWidgets.add(
          Positioned(
            left: left,
            top: top,
            width: tileSize,
            height: tileSize,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Image.network(
                  fallbackUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: tileSize,
                      height: tileSize,
                      color: const Color(0xFFE2E8F0),
                    );
                  },
                );
              },
            ),
          ),
        );
      }
    }

    return Container(
      color: const Color(0xFFF1F5F0),
      child: Stack(
        children: tileWidgets,
      ),
    );
  }
}

/// Canvas painter drawing safe-zone perimeter,
/// home marker, patient position with accuracy circle, and breadcrumbs.
class _MapCanvasPainter extends CustomPainter {
  final double centerLat;
  final double centerLon;
  final double zoom;
  final MapCoordinate? homeLocation;
  final double? safeZoneRadiusMeters;
  final MapCoordinate? patientLocation;
  final double? patientAccuracyMeters;
  final List<MapCoordinate> movementTrail;
  final GeofenceVisualState visualState;

  _MapCanvasPainter({
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    this.homeLocation,
    this.safeZoneRadiusMeters,
    this.patientLocation,
    this.patientAccuracyMeters,
    required this.movementTrail,
    required this.visualState,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2.0;
    final centerY = size.height / 2.0;

    // 1. Draw Movement Breadcrumbs (Trail)
    if (movementTrail.length > 1) {
      final trailPaint = Paint()
        ..color = const Color(0xFF3B82F6).withOpacity(0.7)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      bool first = true;
      for (final pt in movementTrail) {
        final screenPos = _latLonToScreen(
          pt.latitude,
          pt.longitude,
          centerLat,
          centerLon,
          zoom,
          centerX,
          centerY,
        );
        if (first) {
          path.moveTo(screenPos.dx, screenPos.dy);
          first = false;
        } else {
          path.lineTo(screenPos.dx, screenPos.dy);
        }
      }
      canvas.drawPath(path, trailPaint);

      // Draw small trail dots
      final dotPaint = Paint()..color = const Color(0xFF2563EB);
      for (final pt in movementTrail) {
        final p = _latLonToScreen(
          pt.latitude,
          pt.longitude,
          centerLat,
          centerLon,
          zoom,
          centerX,
          centerY,
        );
        canvas.drawCircle(p, 3.0, dotPaint);
      }
    }

    // 3. Draw Safe-Zone Perimeter Circle
    if (homeLocation != null &&
        safeZoneRadiusMeters != null &&
        safeZoneRadiusMeters! > 0) {
      final homeScreen = _latLonToScreen(
        homeLocation!.latitude,
        homeLocation!.longitude,
        centerLat,
        centerLon,
        zoom,
        centerX,
        centerY,
      );

      final metersPerPixel = _metersPerPixelAt(homeLocation!.latitude, zoom);
      final pixelRadius = safeZoneRadiusMeters! / metersPerPixel;

      Color fillColor;
      Color strokeColor;

      switch (visualState) {
        case GeofenceVisualState.inside:
          fillColor = const Color(0xFF10B981).withOpacity(0.18);
          strokeColor = const Color(0xFF059669);
          break;
        case GeofenceVisualState.outside:
          fillColor = const Color(0xFFEF4444).withOpacity(0.18);
          strokeColor = const Color(0xFFDC2626);
          break;
        case GeofenceVisualState.uncertain:
          fillColor = const Color(0xFFF59E0B).withOpacity(0.18);
          strokeColor = const Color(0xFFD97706);
          break;
        case GeofenceVisualState.inactive:
          fillColor = const Color(0xFF0F766E).withOpacity(0.15);
          strokeColor = const Color(0xFF0F766E);
          break;
      }

      final circleFillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      final circleStrokePaint = Paint()
        ..color = strokeColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(homeScreen, pixelRadius, circleFillPaint);
      canvas.drawCircle(homeScreen, pixelRadius, circleStrokePaint);
    }

    // 4. Draw Home Marker Pin
    if (homeLocation != null) {
      final homeScreen = _latLonToScreen(
        homeLocation!.latitude,
        homeLocation!.longitude,
        centerLat,
        centerLon,
        zoom,
        centerX,
        centerY,
      );
      _drawHomePin(canvas, homeScreen);
    }

    // 5. Draw Patient Location Marker & Accuracy Halo
    if (patientLocation != null) {
      final patientScreen = _latLonToScreen(
        patientLocation!.latitude,
        patientLocation!.longitude,
        centerLat,
        centerLon,
        zoom,
        centerX,
        centerY,
      );

      // Accuracy halo
      if (patientAccuracyMeters != null && patientAccuracyMeters! > 0) {
        final mpp = _metersPerPixelAt(patientLocation!.latitude, zoom);
        final accRadius = (patientAccuracyMeters! / mpp).clamp(6.0, 300.0);

        final haloPaint = Paint()
          ..color = const Color(0xFF3B82F6).withOpacity(0.20)
          ..style = PaintingStyle.fill;
        final haloBorder = Paint()
          ..color = const Color(0xFF2563EB).withOpacity(0.40)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

        canvas.drawCircle(patientScreen, accRadius, haloPaint);
        canvas.drawCircle(patientScreen, accRadius, haloBorder);
      }

      _drawPatientPin(canvas, patientScreen, visualState);
    }
  }

  void _drawHomePin(Canvas canvas, Offset position) {
    const pinRadius = 16.0;

    // Pin shadow
    canvas.drawCircle(
      position.translate(0, 2),
      pinRadius,
      Paint()..color = Colors.black.withOpacity(0.2),
    );

    // Pin circle
    final pinPaint = Paint()
      ..color = const Color(0xFF174D43)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, pinRadius, pinPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(position, pinRadius, borderPaint);

    // Draw little roof / home icon shape
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(position.dx, position.dy - 7)
      ..lineTo(position.dx + 7, position.dy)
      ..lineTo(position.dx + 5, position.dy)
      ..lineTo(position.dx + 5, position.dy + 6)
      ..lineTo(position.dx - 5, position.dy + 6)
      ..lineTo(position.dx - 5, position.dy)
      ..lineTo(position.dx - 7, position.dy)
      ..close();
    canvas.drawPath(path, iconPaint);
  }

  void _drawPatientPin(
      Canvas canvas, Offset position, GeofenceVisualState state) {
    const pinRadius = 14.0;

    Color pinColor;
    switch (state) {
      case GeofenceVisualState.inside:
        pinColor = const Color(0xFF10B981);
        break;
      case GeofenceVisualState.outside:
        pinColor = const Color(0xFFEF4444);
        break;
      case GeofenceVisualState.uncertain:
        pinColor = const Color(0xFFF59E0B);
        break;
      case GeofenceVisualState.inactive:
        pinColor = const Color(0xFF2563EB);
        break;
    }

    // Outer pulse ring
    canvas.drawCircle(
      position,
      pinRadius + 4,
      Paint()..color = pinColor.withOpacity(0.25),
    );

    // Solid pin
    canvas.drawCircle(
      position,
      pinRadius,
      Paint()..color = pinColor,
    );

    canvas.drawCircle(
      position,
      pinRadius,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Person dot in center
    canvas.drawCircle(
      position,
      4.0,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _MapCanvasPainter old) {
    return old.centerLat != centerLat ||
        old.centerLon != centerLon ||
        old.zoom != zoom ||
        old.homeLocation != homeLocation ||
        old.safeZoneRadiusMeters != safeZoneRadiusMeters ||
        old.patientLocation != patientLocation ||
        old.patientAccuracyMeters != patientAccuracyMeters ||
        old.movementTrail != movementTrail ||
        old.visualState != visualState;
  }
}

// ----------------- Web Mercator Math Helpers -----------------

Offset _latLonToWorldPixels(double lat, double lon, double zoom) {
  final scale = math.pow(2.0, zoom).toDouble() * 256.0;
  final x = ((lon + 180.0) / 360.0) * scale;
  final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
  final y = (0.5 - math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) *
      scale;
  return Offset(x, y);
}

MapCoordinate _worldPixelsToLatLon(double x, double y, double zoom) {
  final scale = math.pow(2.0, zoom).toDouble() * 256.0;
  final lon = (x / scale) * 360.0 - 180.0;
  final n = math.pi - (2.0 * math.pi * y) / scale;
  final lat = (180.0 / math.pi) * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  return MapCoordinate(lat, lon);
}

Offset _latLonToScreen(
  double lat,
  double lon,
  double centerLat,
  double centerLon,
  double zoom,
  double screenCenterX,
  double screenCenterY,
) {
  final targetWorld = _latLonToWorldPixels(lat, lon, zoom);
  final centerWorld = _latLonToWorldPixels(centerLat, centerLon, zoom);
  return Offset(
    screenCenterX + (targetWorld.dx - centerWorld.dx),
    screenCenterY + (targetWorld.dy - centerWorld.dy),
  );
}

double _metersPerPixelAt(double lat, double zoom) {
  return (156543.03392 * math.cos(lat * math.pi / 180.0)) / math.pow(2.0, zoom);
}
