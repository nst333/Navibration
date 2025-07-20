import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  final List<LatLng> routePoints;
  const MapPage({Key? key, this.routePoints = const []}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _center = LatLng(37.572950, 126.979357);
  final _zoom = 13.0;

  // 사용할 스타일들 정의
  final Map<String, String> _styles = {
    'OSM Standard': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'OpenTopoMap': 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    'Stamen Toner': 'https://tiles.stadiamaps.com/tiles/stamen_toner/{z}/{x}/{y}@2x.png',
    'CartoDB Light': 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
    'CartoDB Dark': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
  };

  String _currentStyleName = 'OSM Standard';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlutterMap(
        options: MapOptions(initialCenter: _center, initialZoom: _zoom),
        children: [
          TileLayer(
            urlTemplate: _styles[_currentStyleName]!,
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
            )
        ],
      ),
    );
  }
}
