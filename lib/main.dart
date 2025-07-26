import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navibration/map.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(
      MaterialApp(
        theme: ThemeData(
            fontFamily: 'NotoSansKR'
        ),
        home: MyApp(),
        debugShowCheckedModeBanner: false,
      ),
  );
}
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

  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  bool isMenuOpen = false;

  bool _submitted = false;
  bool _focused = false;
  bool _showMap = false;
  Map<String, dynamic>? _pathData;

  Map<LatLng, double> angleData = {};

  static const _animDuration = Duration(milliseconds: 500);

  final Map<String, String> _pathModes = {
    "기본" : "0",
    "대로 우선" : "4",
    "최단 거리" : "10",
    "최단 거리 + 계단 제외" : "30"
  };
  String _pathMode = "기본";

  final List<int> _pathCountList = List.generate(11, (index) => index + 5);
  int _pathCount = 10;

  final FlutterTts _tts = FlutterTts();

  double? _lastHeading;
  bool _isStable = false;
  Timer? _stabilityTimer;
  Timer? _confirmationTimer;
  double _stabilityThreshold = 3;

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

    _focusNode.addListener(() {
      setState(() {
        _focused = _focusNode.hasFocus;
      });
    });

    _animController = AnimationController(
      vsync: this,
      duration: _animDuration
    );

    _slideAnim = Tween<Offset>(
      begin: Offset(-1, 0),
      end: Offset(0, 0)
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut
    ));

    //_tts.setLanguage("ko-KR");
    //_tts.setVoice({"name": "ko-kr-x-ism-local", "locale": "ko-KR"});
    //_tts.setVolume(1);
    //_tts.setSpeechRate(1);
  }

  void toggleMenu() {
    setState(() {
      if (isMenuOpen) {
        _animController.reverse();
      } else {
        _animController.forward();
      }
      isMenuOpen = !isMenuOpen;
    });
  }

  Future<void> _onSearchSubmitted(String keyword) async {
    String value = _controller.text;
    if (value.isNotEmpty) {
      final places = await APIService.findLatLngByName(value, _pathCount);
      if (places.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('장소를 찾을 수 없습니다.'),
          )
        );
        _controller.clear();
        return;
      }

      APIService.showDestinationDialog(
          context,
          places,
          (name, pos) => _handleSelectedDestination(name, pos)
      );
    } else {
      setState(() {
        _submitted = false;
        _showMap = false;
      });
    }
  }

  void _startListeningToCompass() {
    print("_startListeningToCompass run");
    FlutterCompass.events?.listen((event) {
      double? currentHeading = event.heading;

      if (currentHeading == null) return;

      if (_lastHeading != null) {
        double delta = _angleDifference(currentHeading, _lastHeading!);

        if (delta < _stabilityThreshold) {
          _onStableHeading(currentHeading);
        } else {
          _cancelStabilityProcess();
        }

        _lastHeading = currentHeading;
      }
    });
  }

  double _angleDifference(double a, double b) {
    double diff = (a - b).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  void _onStableHeading(double heading) {
    if (_isStable) return;

    _stabilityTimer ??= Timer(Duration(seconds: 2), () {
      _isStable = true;
      _speakAndConfirm(heading);
    });
  }

  void _cancelStabilityProcess() {
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    _confirmationTimer?.cancel();
    _confirmationTimer = null;
    _isStable = false;
  }

  void _speakAndConfirm(double heading) async {
    await _tts.speak(
        "원하는 위치에 두었나요? 3초간 응답이 없으면 설정이 완료된 것으로 간주해 길 안내가 시작됩니다.");

    _confirmationTimer = Timer(Duration(seconds: 3), () {
      _setStartDirection(heading);
    });
  }

  void _setStartDirection(double heading) {
    debugPrint("🧭 설정 완료! 시작 방향은 $heading 도");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🧭 설정 완료! 시작 방향은 $heading 도"),
      )
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleSelectedDestination(String name, LatLng pos) async {
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
          content: Text('위치 권한이 영구적으로 거부되었습니다.'),
        ),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
    );


    final routeData = await APIService.fetchPedestrianRoute(
      startLat: position.latitude,
      startLng: position.longitude,

      endLat: APIService.selectedPos.latitude,
      endLng: APIService.selectedPos.longitude,

      pathMode: _pathModes[_pathMode]!
    );

    if (routeData != []) {
      _pathData = routeData;
      calculateAngleData();

      setState(() {
        _submitted = true;
        _showMap = true;
      });
      _focusNode.unfocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("경로를 계산할 수 없습니다.\n인터넷이 연결되었는지 확인해주세요."),
        )
      );
    }
  }

  void calculateAngleData() {
    // Bearing Formula
    // θ = atan2( sin Δλ ⋅ cos φ2 , cos φ1 ⋅ sin φ2 − sin φ1 ⋅ cos φ2 ⋅ cos Δλ )

    List<LatLng> points = _pathData!["linePoints"];

    for (int i = 1; i < points.length; i++) {
      LatLng from = points[i-1];
      LatLng to   = points[i];

      double phi1 = degToRadian(from.latitude);
      double phi2 = degToRadian(to.latitude);
      double lambda1 = degToRadian(from.longitude);
      double lambda2 = degToRadian(to.longitude);

      double angle = radianToDeg(
        atan2(
            sin(lambda2 - lambda1) * cos(phi2),

            cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(lambda2 - lambda1)
        )
      );

      angleData[from] = angle;
    }
  }

  String getAngleString() {
    String result = '';

    for (LatLng point in angleData.keys) {
      result += '${point.toString()}  ----->  ${angleData[point].toString()}\n';
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Color.fromRGBO(0, 47, 255, 1);
    final fillColor = _submitted ? borderColor : Colors.white;
    final textColor = _submitted ? Colors.white : borderColor;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth  = MediaQuery.of(context).size.width;


    return Scaffold(
        backgroundColor: Color.fromRGBO(250, 250, 250, 1),
        body: Stack(
          children: [
            // MapPage
            if (_showMap && _pathData != null && _pathData!["linePoints"] != null)
              AnimatedOpacity(
                duration: Duration(milliseconds: _animDuration.inMilliseconds + 200),
                opacity: _showMap ? 1 : 0,
                child: MapPage(
                  routePoints: _pathData?["linePoints"] ?? [],
                  startPoint: _pathData?['startPoint'] ?? LatLng(0, 0),
                  endPoint: _pathData?['endPoint'] ?? LatLng(0, 0),
                ),
              ),

            // 로고
            Positioned(
              top: 100, // 적당히 조절해
              left: (screenWidth - screenWidth * 0.6) / 2,
              child: AnimatedOpacity(
                opacity: _submitted || _focused ? 0 : 1,
                duration: _animDuration,
                child: SizedBox(
                  width: screenWidth * 0.6,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.asset(
                      'assets/images/fffffffffffff.png',
                      fit: BoxFit.contain,
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

                  SizedBox(height: 30,),

                  Text(
                    "가끔 경로를 찾지 못하고 현재 화면에서 멈출 수 있습니다!",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12
                    ),
                  )
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
                              CupertinoButton(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      width: 2,
                                      color: borderColor,
                                    ),
                                  ),
                                  alignment: Alignment.center, // 텍스트 위치 맞추기
                                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  child: Text(
                                    '시작',
                                    style: TextStyle(
                                      color: borderColor,
                                    ),
                                  ),
                                ),
                                onPressed: () {
                                  _tts.speak("기기를 원하는 위치에 두고 방향이 크게 틀어지지 않게 주의하세요.");
                                  _tts.stop();
                                  _startListeningToCompass();
                                  _tts.speak("길 안내를 시작합니다!");
                                  _tts.stop();

                                  // TODO : 안내 신호 보내기

                                  Clipboard.setData(
                                      ClipboardData(text: getAngleString())
                                  );

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('각 데이터가 복사됨.'),
                                    ),
                                  );
                                },
                              )
                            ],
                          )
                        ],
                      )
                  ),
                ),
              ),
            ),

            if (isMenuOpen)
              GestureDetector(
                onTap: toggleMenu,
                child: Container(
                  color: Colors.transparent, // 투명
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

            // 설정탭
            SlideTransition(
              position: _slideAnim,
              child: Container(
                width: (screenWidth * 55/100),

                decoration: BoxDecoration(
                  color: Color.fromRGBO(250, 250, 250, 1),
                  borderRadius: BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
                  border: Border.all(
                    width: 2,
                    color: borderColor,
                  )
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 100,),

                    Column(
                      children: [
                        Text(
                          "경로 성격 설정",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: textColor
                          ),
                        ),
                        SizedBox(height: 10,),
                        Padding(
                            padding: EdgeInsets.only(left: 30),
                            child: DropdownButton(
                              value: _pathMode,
                              hint: const Text("경로 설정"),
                              items: _pathModes.keys.map((item) {
                                return DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _pathMode = value!;
                                });
                              },
                            )
                        ),



                        // 나중에 설정값 추가할 때, 구분선 넣고 추가하기
                        SizedBox(height: 20,),

                        Divider(
                          color: Colors.grey,
                          thickness: 1,
                          height: 20,
                          indent: 30,
                          endIndent: 30,
                        ),

                        SizedBox(height: 20,),



                        Text(
                          "목적지 검색 개수",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: textColor
                          ),
                        ),
                        Text(
                          '$_pathCount',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.black
                          ),
                        ),
                        SizedBox(height: 10,),
                        CupertinoButton(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                width: 2,
                                color: borderColor,
                              ),
                            ),
                            alignment: Alignment.center, // 텍스트 위치 맞추기
                            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                            child: Text(
                              '개수 선택',
                              style: TextStyle(
                                color: textColor,
                              ),
                            ),
                          ),
                          onPressed: () {
                            showCupertinoModalPopup(
                              context: context,
                              builder: (_) => Container(
                                height: 300,
                                color: Colors.white,
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      alignment: Alignment.centerRight,
                                      child: CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        child: Text(
                                          "완료",
                                          style: TextStyle(color: Colors.black),
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                    Expanded(
                                      child: CupertinoPicker(
                                        itemExtent: 40,
                                        scrollController: FixedExtentScrollController(
                                          initialItem: _pathCount - 5,
                                        ),
                                        onSelectedItemChanged: (index) {
                                          setState(() {
                                            _pathCount = _pathCountList[index];
                                          });
                                        },
                                        children: _pathCountList
                                            .map((e) => Center(child: Text('$e')))
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Visibility(
              visible: !_submitted,
              child: AnimatedOpacity(
                opacity: _submitted ? 0 : 1,
                duration: _animDuration,
                child: SafeArea(
                  child: Container(
                    height: 100,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: AnimatedIcon(
                            icon: AnimatedIcons.menu_close,
                            progress: _animController,
                            color: Colors.black,
                            size: 28,
                          ),
                          onPressed: toggleMenu,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          ],
        )
    );
  }
}

class APIService {
  static const _appKey = 'oTTP497zZS5eps0zfeuTJ16mujxhkO2Y6DSF3k05';
  static String selectedName = "";
  static LatLng selectedPos = LatLng(0, 0);

  static void showDestinationDialog(
      BuildContext context,
      List<Map<String, LatLng>> places,
      void Function(String name, LatLng pos) onPlaceSelected
      ) {

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                width: 2,
                color: Color.fromRGBO(0, 47, 255, 1) // borderColor
              ),
              color: Colors.white
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: places.length,
                      separatorBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 0),
                        child: Divider(
                          color: Colors.grey,
                          thickness: 1,
                        ),
                      ),
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            selectedName = places[index].keys.first.split("|||").first;
                            selectedPos = places[index].values.first;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('목적지 선택 완료!\n$selectedName'),
                              ),
                            );

                            Navigator.pop(context);
                            onPlaceSelected(selectedName, selectedPos);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  places[index].keys.first.split("|||").first,
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  places[index].keys.first.split("|||").last,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            )
          ),
        );
      }
    );
  }

  /// 키워드로 POI를 검색해 [이름, 주소, 위도, 경도] 맵의 리스트를 반환
  static Future<List<Map<String, LatLng>>> findLatLngByName(String keyword, int count) async {
    if (keyword.isEmpty) return [];

    final uri = Uri.https(
      'apis.openapi.sk.com',
      '/tmap/pois',
      {
        'version': '1',
        'format': 'json',
        'searchKeyword': keyword,
        'resCoordType': 'WGS84GEO',
        'count': count.toString(),
      },
    );

    final headers = {'appKey': _appKey};

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      //print(data.toString());

      final pois = data["searchPoiInfo"]["pois"]["poi"];
      //print(pois.toString());
      List<Map<String, LatLng>> result = [];

      // 이름 ||| uA + mA + lA
      for (final poi in pois) {
        String key = poi["name"] + "|||" + (
            poi["upperAddrName"] + " " +
                poi["middleAddrName"] + " " +
                poi["lowerAddrName"]
        );
        LatLng value = LatLng(double.parse(poi["pnsLat"]), double.parse(poi["pnsLon"]));

        result.add({key: value});
      }

      return result;
    } else {
      print('API 오류: ${response.statusCode}');
      return [];
    }

    // try {
    //
    // } catch (e) {
    //   print('요청 실패: $e');
    //   print(e.toString());
    //   return [];
    // }
  }

  /// 출발/도착 좌표로 보행자 경로를 탐색해 [총 거리, 총 시간, 경로 좌표 리스트, 마커 리스트]를 반환
  static Future<Map<String, dynamic>?> fetchPedestrianRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required String pathMode
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
      'searchOption': pathMode,
      'reqCoordType': 'WGS84GEO',
      'startName': '출발지',
      'endName': '도착지',
    };

    final response = await http.post(uri, headers: headers, body: body);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);

    final features = data["features"];

    List<String> descriptions = [];
    List<LatLng> linePoints = [];

    final firstFeatures = features.firstWhere(
      (f) => (f["properties"]?["totalDistance"] != null) && (f["properties"]?["totalTime"] != null),
      orElse: () => null
    );
    if (firstFeatures == null) return null;

    double totalKm = features[0]["properties"]["totalDistance"] / 1000;
    double totalHour = features[0]["properties"]["totalTime"] / 60;

    for (final feature in features) {
      // Point면 PolyLine 용 꼭짓점 모으기
      // LineString이면 이동 설명 모으기

      if (feature["geometry"]["type"] == "Point") {
        linePoints.add(LatLng(feature["geometry"]["coordinates"][1], feature["geometry"]["coordinates"][0]));
      }
      else if (feature["geometry"]["type"] == "LineString") {
        descriptions.add(feature["properties"]["description"]);
      }
    }

    return {
      'startPoint' : LatLng(startLat, startLng),
      'endPoint'   : LatLng(endLat, endLng),

      'totalKm' : totalKm,
      'totalHour' : totalHour,
      'descriptions' : descriptions,
      'linePoints' : linePoints
    };
  }
}
