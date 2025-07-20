import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navibration/map.dart';
import 'package:navibration/staticvar.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(MyApp());
//void main() => runApp(MapPage());
//void main() => runApp(SearchMapPage());

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _submitted = false;
  bool _showMap = false;
  List<LatLng> _routePoints = [];

  static const _animDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _controller.text.isNotEmpty) {
        if (!_focusNode.hasFocus && _controller.text.isNotEmpty) {
          _onSearchSubmitted(_controller.value.text);
        }

        setState(() => _submitted = true);
      }
    });

    _controller.addListener(() {
      if (_controller.text.isEmpty && _submitted) {
        setState(() {
          _submitted = false;
          _showMap = false;
        });
      }
    });
  }

  Future<void> _onSearchSubmitted(String value) async {
    if (value.isNotEmpty) {
      final results = await TmapService.foundLatLngByName(value);
      if (results.isEmpty) return;

      final selection = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('목적지를 선택하세요'),
          children: results.map((res) => SimpleDialogOption(
            child: Text(res['name'] as String),
            onPressed: () => Navigator.pop(context, res),
          )).toList(),
        ),
      );
      if (selection == null) return;

      final endLat = selection['lat'] as double;
      final endLng = selection['lng'] as double;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final startLat = position.latitude;
      final startLng = position.longitude;

      final routeData = await TmapService.fetchPedestrianRoute(
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
      );
      if (routeData == null) return;

      final coords = routeData['features'][0]['geometry']['coordinates'] as List;
      _routePoints = coords.map((pt) => LatLng(pt[1] as double, pt[0] as double)).toList();

      setState(() {
        _submitted = true;
        _showMap = true;
      });
      _focusNode.unfocus();

    } else {
      setState(() {
        _submitted = false;
        _showMap = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void onPressStar() {
    print("Star Pressed");
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Color.fromRGBO(0, 47, 255, 1);
    final fillColor = _submitted ? borderColor : Colors.white;
    final textColor = _submitted ? Colors.white : borderColor;
    final screenHeight = MediaQuery.of(context).size.height;


    return MaterialApp(
      theme: themeData,
      home: Scaffold(
        backgroundColor: Color.fromRGBO(250, 250, 250, 1),
        body: Stack(
          children: [
            // MapPage
            AnimatedOpacity(
              duration: Duration(milliseconds: _animDuration.inMilliseconds + 200),
              opacity: _showMap ? 1 : 0,
              child: MapPage(routePoints: _routePoints,),
            ),

            // 로고
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 100),
              child: AnimatedOpacity(
                opacity: _submitted ? 0 : 1,
                duration: _animDuration,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    child: Image.asset(
                      'assets/images/icon_0.png',
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),

            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 장소 검색
                  AnimatedPadding(
                    padding: EdgeInsets.only(
                      bottom: _submitted ? (screenHeight / 2) + (screenHeight * (20/100)) : 0,
                    ),
                    duration: _animDuration,
                    curve: Curves.easeInOut,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 45),
                      child: Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(201, 201, 201, 1),
                                spreadRadius: 0,
                                blurRadius: 1,
                                offset: Offset(0, 7),
                              )
                            ]
                        ),

                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                            height: 2,
                          ),
                          decoration: InputDecoration(
                            hint: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search,
                                  color: textColor,
                                  size: 40,
                                ),
                                Text(
                                  "장소 검색",
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 25,
                                  ),
                                )
                              ],
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: fillColor,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: borderColor, width: 2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Color.fromRGBO(0, 58, 255, 1), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onSubmitted: _onSearchSubmitted,
                        ),
                      ),
                    ),
                  ),

                  // 즐겨 찾기
                  AnimatedOpacity(
                    opacity: _submitted ? 0 : 1,
                    duration: _animDuration,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(60),
                        ),
                        padding: EdgeInsets.zero,
                        splashFactory: NoSplash.splashFactory
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 60),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Color.fromRGBO(222, 222, 222, 1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_border),
                                SizedBox(width: 8),
                                Text(
                                  '즐겨찾기',
                                  style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.w500),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            AnimatedPositioned(
              duration: _animDuration,
              curve: Curves.easeOutQuint,
              left: 0,
              right: 0,
              bottom: _submitted ? 0 : -(screenHeight * (30/100)), // 보이지 않도록 화면 아래에 두기
              height: (screenHeight * (30/100)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, -3),
                      ),
                    ],
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Text(_controller.text, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),),
                            Text("장소 이름", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),),
                          ],
                        ),

                        Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                // 버튼 클릭 시 동작
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromRGBO(119, 234, 117, 1),
                                shadowColor: Colors.white,
                                elevation: 5,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(60),
                                ),
                              ),
                              child: const Text(
                                '시작',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          ],
                        )


                      ],
                    )
                  ),
                ),
              ),
            ),
          ],
        )
      ),
    );
  }
}

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
