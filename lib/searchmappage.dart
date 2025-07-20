import 'dart:convert';
import 'package:http/http.dart' as http;

class TmapService {
  static const _appKey = 'oTTP497zZS5eps0zfeuTJ16mujxhkO2Y6DSF3k05';

  /// 키워드로 POI를 검색해 [이름, 주소, 위도, 경도] 맵의 리스트를 반환
  static Future<List<Map<String, dynamic>>> foundLatLngByName(String keyword) async {
    if (keyword.isEmpty) return [];

    final uri = Uri.https(
      'apis.openapi.sk.com',
      '/tmap/pois',
      {
        'version': '1',
        'format': 'json',
        'searchKeyword': keyword,
        'resCoordType': 'WGS84GEO',
        'count': '10',
      },
    );

    final headers = {'appKey': _appKey};

    try {
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pois = data['searchPoiInfo']['pois']['poi'] as List;

        return pois.map((poi) {
          return {
            'name': poi['name'],
            'address': poi['upperAddrName'] +
                ' ' +
                poi['middleAddrName'] +
                ' ' +
                poi['lowerAddrName'] +
                ' ' +
                poi['detailAddrName'],
            'lat': double.tryParse(poi['frontLat'] ?? '') ?? 0.0,
            'lng': double.tryParse(poi['frontLon'] ?? '') ?? 0.0,
          };
        }).toList();
      } else {
        print('API 오류: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('요청 실패: $e');
      return [];
    }
  }

  /// 출발/도착 좌표로 보행자 경로를 탐색해 [총 거리, 총 시간, 경로 좌표 리스트, 마커 리스트]를 반환
  static Future<Map<String, dynamic>?> fetchPedestrianRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final uri = Uri.https(
      'apis.openapi.sk.com',
      '/tmap/routes/pedestrian',
      {
        'version': '1',
        'format': 'json',
      },
    );

    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      'appKey': _appKey,
    };

    final body = {
      'startX': startLng.toString(),
      'startY': startLat.toString(),
      'endX': endLng.toString(),
      'endY': endLat.toString(),
      'reqCoordType': 'WGS84GEO',
      'resCoordType': 'EPSG3857',
      'startName': '출발지',
      'endName': '도착지',
    };

    final response = await http.post(uri, headers: headers, body: body);
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    final features = json['features'] as List<dynamic>;
    if (features.isEmpty) return null;

    final props = features.first['properties'];
    final double distanceKm = (props['totalDistance'] as num) / 1000;
    final double durationMin = (props['totalTime'] as num) / 60;

    final List<Map<String, double>> polyline = [];
    final List<Map<String, dynamic>> markers = [];

    for (var f in features) {
      final geom = f['geometry'];
      if (geom['type'] == 'LineString') {
        final coords = geom['coordinates'] as List;
        for (var coord in coords) {
          polyline.add({'lat': coord[1], 'lng': coord[0]});
        }
      } else if (geom['type'] == 'Point') {
        final props = f['properties'];
        markers.add({
          'lat': geom['coordinates'][1],
          'lng': geom['coordinates'][0],
          'pointType': props['pointType'],
        });
      }
    }

    return {
      'distanceKm': distanceKm,
      'durationMin': durationMin,
      'polyline': polyline,
      'markers': markers,
    };
  }
}
