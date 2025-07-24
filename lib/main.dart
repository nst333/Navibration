import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navibration/map.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  Map<String, dynamic>? pathData;

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
      final places = await TmapService.findLatLngByName(value, _pathCount);
      if (places.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('장소를 찾을 수 없습니다.'),
          )
        );
        _controller.clear();
        return;
      }

      TmapService.showDestinationDialog(
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


    final routeData = await TmapService.fetchPedestrianRoute(
      startLat: position.latitude,
      startLng: position.longitude,

      endLat: TmapService.selectedPos.latitude,
      endLng: TmapService.selectedPos.longitude,

      pathMode: _pathModes[_pathMode]!
    );

    if (routeData != []) {
      pathData = routeData;

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
    final screenWidth  = MediaQuery.of(context).size.width;


    return Scaffold(
        backgroundColor: Color.fromRGBO(250, 250, 250, 1),
        body: Stack(
          children: [
            // MapPage
            if (_showMap && pathData != null && pathData!["linePoints"] != null)
              AnimatedOpacity(
                duration: Duration(milliseconds: _animDuration.inMilliseconds + 200),
                opacity: _showMap ? 1 : 0,
                child: MapPage(
                  routePoints: pathData?["linePoints"] ?? [],
                  startPoint: pathData?['startPoint'] ?? LatLng(0, 0),
                  endPoint: pathData?['endPoint'] ?? LatLng(0, 0),
                ),
              ),

            // 로고
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 100),
              child: AnimatedOpacity(
                opacity: _submitted || _focused ? 0 : 1,
                duration: _animDuration,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Image.asset(
                    'assets/images/fffffinal_icon.png',
                    width: (screenWidth * 40/100),
                    height: (screenHeight * 20/100),
                    cacheWidth: (screenWidth * 0.4).toInt(),
                    cacheHeight: (screenHeight * 0.2).toInt(),
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
                          color: CupertinoColors.activeBlue,
                          child: Text('개수 선택'),
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
                                        child: Text(
                                            "완료",
                                          style: TextStyle(
                                            color: Colors.black
                                          ),
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                    Expanded(
                                      child: CupertinoPicker(
                                        itemExtent: 40,

                                        scrollController: FixedExtentScrollController(
                                          initialItem: _pathCount - 5
                                        ),

                                        onSelectedItemChanged: (index) {
                                          setState(() {
                                            _pathCount = _pathCountList[index];
                                          });
                                        },

                                        children: _pathCountList
                                          .map((e) => Center(child: Text('$e'),))
                                          .toList()
                                      ),
                                    ),
                                  ],
                                ),
                              )
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

class TmapService {
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
