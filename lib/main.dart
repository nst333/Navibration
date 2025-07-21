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
  Map<String, dynamic>? pathData;

  static const _animDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      if (_controller.text.isEmpty && _submitted) {
        setState(() {
          _submitted = false;
          _showMap = false;
        });
      }
    });
  }

  Future<void> _onSearchSubmitted(String keyword) async {
    String value = _controller.text;
    if (value.isNotEmpty) {
      final places = await TmapService.foundLatLngByName(value);
      if (places.isEmpty) return;

      TmapService.showDestinationDialog(context, places);


      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('위치 서비스가 비활성화되어 있습니다.'),
          ),
        );
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('위치 권한이 거부되었습니다.'),
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('위치 권ahan이 영구적으로 거부되었습니다.'),
          ),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );


      final routeData = await TmapService.fetchPedestrianRoute(
          startLat: position.latitude,
          startLng: position.longitude,

          endLat: TmapService.selectedPos.latitude,
          endLng: TmapService.selectedPos.longitude
      );

      if (routeData != null) {
        pathData = routeData;
        // TODO : 경로 표시 -> MapPage 불러올 때 쓰기

        setState(() {
          _submitted = true;
          _showMap = true;
        });
        _focusNode.unfocus();
      }

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('즐겨찾기 기능은 아직 준비 중입니다.'),
      ),
    );
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
              child: MapPage(routePoints: pathData?["linePoints"] ?? [],),
            ),

            // 로고
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 100),
              child: AnimatedOpacity(
                opacity: _submitted ? 0 : 1,
                duration: _animDuration,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Image.asset(
                    'assets/images/icon_0.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('안내 시작 기능은 아직 준비 중입니다.'),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromRGBO(79, 235, 76, 1),
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
  static String selectedName = "";
  static LatLng selectedPos = LatLng(0, 0);

  static void showDestinationDialog(BuildContext context, List<Map<String, LatLng>> places) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: places.length,
                    itemBuilder: (context, index) {
                      return Container(
                        height: 100,
                        child: GestureDetector(
                          child: Column(
                              children: [
                                Text(places[index].keys.first.split("|||").first, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                                Text(places[index].keys.first.split("|||").last, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w300),)
                              ],
                          ),
                          onTap: () {
                            selectedName = places[index].keys.first.split("|||").first;
                            selectedPos = places[index].values.first;
                            Navigator.pop(context);
                          },
                        )
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }

  /// 키워드로 POI를 검색해 [이름, 주소, 위도, 경도] 맵의 리스트를 반환
  static Future<List<Map<String, LatLng>>> foundLatLngByName(String keyword) async {
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
        final pois = data["searchPoiInfo"]["pois"]["poi"];
        List<Map<String, LatLng>> result = [];

        // 이름 ||| uA + mA + lA
        for (final poi in pois) {
          String key = poi["name"] + "|||" + (
            poi["upperAddrName"] + " " +
              poi["middleAddrName"] + " " +
              poi["lowerAddrName"]
          );
          LatLng value = LatLng(double.parse(poi["pnsLat"]), double.parse(poi["pnsLng"]));

          result.add({key: value});
        }

        return result;
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
      'startName': '출발지',
      'endName': '도착지',
    };

    try {
      final response = await http.post(uri, headers: headers, body: body);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);

      final features = data["features"];

      List<String> descriptions = [];
      List<LatLng> linePoints = [];

      double totalKm = double.parse(features[0]["properties"]["totalDistance"]) / 1000;
      double totalHour = double.parse(features[0]["properties"]["totalTime"]) / 60;

      for (final feature in features) {
        // Point면 설명 모으기
        // LineString이면 PolyLine용 포인트 모으기

        if (feature["geometry"]["type"] == "Point") {
          descriptions.add(feature["properties"]["description"]);
        }
        else if (feature["geometry"]["type"] == "LineString") {
          final coordinates = feature["geometry"]["coordinates"];
          for (final coordinate in coordinates) {
            linePoints.add(LatLng(double.parse(coordinate[1]), double.parse(coordinate[0])));
          }
        }
      }

      return {
        'totalKm' : totalKm,
        'totalHour' : totalHour,
        'descriptions' : descriptions,
        'linePoints' : linePoints
      };
    } catch (e) {
      print('경로 요청 실패: $e');
      return null;
    }
  }
}
