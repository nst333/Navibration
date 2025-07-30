import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  final List<LatLng> routePoints;
  final LatLng startPoint;
  final LatLng endPoint;
  final LatLng currentPos;
  const MapPage(
      {
        Key? key,
        required this.routePoints,
        required this.startPoint,
        required this.endPoint,
        required this.currentPos
      }
      ) : super(key: key
  );

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  double? _heading;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;

  // 사용할 스타일들 정의
  Map<String, String> _styles = {
    'OSM Standard': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'OpenTopoMap': 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    'Stamen Toner': 'https://tiles.stadiamaps.com/tiles/stamen_toner/{z}/{x}/{y}@2x.png',
    'CartoDB Light': 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
    'CartoDB Dark': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
  };

  String _currentStyleName = 'OSM Standard';

  @override
  void initState() {
    super.initState();
    _initCompass();
  }

  void _initCompass() {
    _compassStream = FlutterCompass.events?.listen((event) {
      setState(() {
        _heading = event.heading;
      });
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds(widget.startPoint, widget.endPoint),
            padding: EdgeInsets.all(50)
          )
        ),

        children: [
          TileLayer(
            urlTemplate: _styles[_currentStyleName]!,
            userAgentPackageName: 'io.github.nst33',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: widget.currentPos,
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_heading != null)
                      Transform.rotate(
                        angle: (_heading! * math.pi) / 180,
                        child: Icon(Icons.arrow_circle_up_rounded, size: 50, color: Colors.blue),
                      )
                  ],
                )
              )
            ],
          ),
          if (widget.routePoints.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.routePoints,
                  strokeWidth: 4,
                  color: Colors.blue
                )
              ],
            ),
        ],
      ),
    );
  }
}
