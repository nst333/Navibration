import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navibration/map.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(
      MaterialApp(
        theme: ThemeData(
            fontFamily: 'NotoSansKR'
        ),
        home: MyApp(),
        //home: CompassTestPage(),
        debugShowCheckedModeBanner: true,
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
  bool _isEnterSplash = true;
  Map<String, dynamic>? _pathData;
  Map<LatLng, double> _angleData = {};

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

  double? _lastHeading;
  double _stabilityThreshold = 3;
  double? _finalHeading;
  int _stableTicks = 0;
  final int _requiredStableTicks = 20;
  bool _headingConfirmed = false;
  bool _startSoundPlayed = false;
  bool _startNavi = false;

  bool _isShowingPopup = false;
  BuildContext? _popupContext;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<CompassEvent>? _compassSub;

  double _angleThreshold = 10;

  static const double earthRadius = 6371;


  @override
  void initState() {
    super.initState();

    Future.delayed(Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isEnterSplash = false;
        });
      }
    });

    _controller.addListener(() {
      if (_controller.text.isEmpty && _submitted) {
        if (mounted) {
          setState(() {
            _submitted = false;
            _showMap = false;
          });
        }
      }
    });

    _focusNode.addListener(() {
      if (mounted) {
        final hasFocus = _focusNode.hasFocus;
        if (_focused != hasFocus) {
          setState(() {
            _focused = hasFocus;
          });
        }
      }
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
      playAudio("wait_a_minute.mp3");
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
    _compassSub?.cancel();
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
        desiredAccuracy: LocationAccuracy.bestForNavigation
    );


    final routeData = await APIService.fetchPedestrianRoute(
      startLat: position.latitude,
      startLng: position.longitude,

      endLat: APIService.selectedPos.latitude,
      endLng: APIService.selectedPos.longitude,

      pathMode: _pathModes[_pathMode]!
    );

    if (routeData != [] && routeData?["linePoints"] != null && routeData?["linePoints"] is List<LatLng>) {
      _pathData = routeData;

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

  void _showDirectionPopup(String message) {
    if (_isShowingPopup) return; // 이미 열려 있으면 다시 열지 않음

    _isShowingPopup = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        _popupContext = dialogContext;
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Color.fromRGBO(0, 47, 255, 1),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hideDirectionPopup() {
    if (_isShowingPopup && _popupContext != null) {
      Navigator.of(_popupContext!).pop();
      _isShowingPopup = false;
      _popupContext = null;
    }
  }

  void _startListeningToCompass() {
    print("_startListeningToCompass run");

    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen((event) async {
      final currentHeading = event.heading;
      if (currentHeading == null) return;

      if (_lastHeading != null) {
        double delta = _angleDifference(currentHeading, _lastHeading!);

        if (!_headingConfirmed) {
          if (delta < _stabilityThreshold) {
            _stableTicks++;

            if (_stableTicks == 1) {
              _showDirectionPopup("📡 방향 안정화 중입니다...\n핸드폰을 고정해 주세요.");
            }

            if (_stableTicks >= _requiredStableTicks) {
              // debugPrint("🧭 방향 안정화 확정 (연속 $_requiredStableTicks 프레임)");
              // _headingConfirmed = true;
              // await _speakAndConfirm(currentHeading);

              debugPrint("🧭 방향 안정화 확정됨");
              _headingConfirmed = true;

              _showDirectionPopup("🧭 방향 안정화 확정됨");
              await Future.delayed(Duration(seconds: 1)); // 완료 메시지 보여주기

              _hideDirectionPopup();
              await _speakAndConfirm(currentHeading);
            }
          } else {
            if (_stableTicks > 0) {
              debugPrint("🌀 방향 흔들림 감지됨. 안정 카운트 초기화");
            }
            _stableTicks = 0;
          }
        }
      }

      _lastHeading = currentHeading;
      setState(() {});
    });
  }

  Future<void> _setStartDirection(double heading) async {
    debugPrint("🧭 설정 완료! 시작 방향은 $heading 도");

    _finalHeading = heading;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🧭 설정 완료! 시작 방향은 $heading 도"),
        )
    );
  }

  Future<void> playAudio(String filename, {VoidCallback? onComplete}) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/$filename'));

      Duration? duration = await _player.getDuration();
      await Future.delayed(duration ?? Duration(seconds: 3));

      if (onComplete != null) onComplete();
    } catch (e) {
      debugPrint("🔊 오디오 재생 오류: $e");
    }
  }

  // void _speakAndConfirm(double heading) async {
  //   if (_confirmationTimer != null) return;
  //
  //   await playAudio("position_check.mp3");
  //
  //   _confirmationTimer = Timer(Duration(seconds: 3), () async {
  //     await _setStartDirection(heading);
  //
  //     await playAudio("start_navi.mp3");
  //   });
  // }

  Future<void> _speakAndConfirm(double heading) async {
    if (_startSoundPlayed) return;

    debugPrint("🧭 방향 안정화 감지됨. 확인 및 설정 시작");

    await playAudio("position_check.mp3");

    await Future.delayed(Duration(seconds: 3)); // 사용자 확인 기다림

    await _setStartDirection(heading);

    await playAudio("start_navi.mp3");
    _startSoundPlayed = true;
  }

  void calculateAngleData() {
    List<LatLng> points = _pathData!["linePoints"];

    for (int i = 1; i < points.length; i++) {
      _angleData[points[i-1]] = calculateBearing(points[i-1], points[i]);
    }
  }

  double _angleDifference(double a, double b) {
    double diff = (a - b).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  double _toRelativeAngle(double angle) {
    return (angle - _finalHeading! + 360) % 360;
  }

  double calculateBearing(LatLng a, LatLng b) {
    // Bearing Formula
    // θ = atan2( sin Δλ ⋅ cos φ2 , cos φ1 ⋅ sin φ2 − sin φ1 ⋅ cos φ2 ⋅ cos Δλ )

    double phi1 = degToRadian(a.latitude);
    double phi2 = degToRadian(b.latitude);
    double lambda1 = degToRadian(a.longitude);
    double lambda2 = degToRadian(b.longitude);

    return _toRelativeAngle(radianToDeg(
        atan2(
            sin(lambda2 - lambda1) * cos(phi2),

            cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(lambda2 - lambda1)
        )
    ));
  }

  double calculateHarverSine(LatLng a, LatLng b) {
    // HaverSine Formula
    // θ = d/r
    // hav(θ) = hav(Δφ) + cos(φ1)cos(φ2)hav(Δλ)
    //        = sin^2(θ/2) = (1-cos(θ)/2
    // d = r * archav(h) = 2r * arcsin(sqrt(h))
    //   = 2r * arcsin(sqrt(hav(Δφ) + cos(φ1)cos(φ2)hav(Δλ)
    //   = 2r * arcsin(sqrt(sin^2(Δφ/2) + cos(φ1)cos(φ2)sin^2(Δλ/2)))

    double lat1 = degToRadian(a.latitude);
    double lat2 = degToRadian(b.latitude);

    double lon1 = degToRadian(a.longitude);
    double lon2 = degToRadian(b.longitude);

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    return 2*earthRadius * asin(
      sqrt(
        pow(sin(dLat/2), 2)
            + cos(lat1) * cos(lat2) * pow(sin(dLon/2), 2)
      )
    );
  }

  String getAngleString() {
    String result = '';

    for (var entry in _angleData.entries) {
      result += '${entry.key.toString()}  ----->  ${entry.value.toStringAsFixed(2)}\n';
    }

    return result;
  }

  String convertAngleToNSWE(double angle) {
    angle %= 360;

    if (angle >= 315 || angle < 45) return 'N';
    if (angle >= 45 && angle < 135) return 'E';
    if (angle >= 135 && angle < 225) return 'S';
    if (angle >= 225 && angle < 315) return 'W';

    return "Unknown";
  }

  Future<Map<String, double>> calculateVibrationType(LatLng target) async {
    // 사용자 위치랑 매개변수 위치
    Position currentPos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      )
    );

    double angle = calculateBearing(
        LatLng(currentPos.latitude, currentPos.longitude),
        target
    );

    String type = "";
    if (angle >= _angleThreshold && angle < 180 - _angleThreshold) {
      type = "R";
    }
    else if (angle > 180 + _angleThreshold && angle < 360 - _angleThreshold) {
      type = "L";
    }
    else if (angle >= 180 - _angleThreshold && angle <= 180 + _angleThreshold) {
      type = "U";
    } else {
      type = "S";
    }

    return {
      type: angle
    };
  }

  LatLng? _getNearestCorner(LatLng pos) {
    double minDist = double.infinity;
    LatLng? closest;

    for (LatLng corner in _angleData.keys) {
      final dist = calculateHarverSine(pos, corner);

      if (dist < minDist) {
        minDist = dist;
        closest = corner;
      }
    }

    return closest;
  }

  void _startNavigation() {
    _compassSub = FlutterCompass.events?.listen((event) async {
      // 다음 회전 계산하기
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation
        )
      );

      final nextCorner = _getNearestCorner(pos as LatLng);
      Map<String, double> nextVibrationType = await calculateVibrationType(nextCorner!);
      String type = nextVibrationType.keys.first;
      double angle = nextVibrationType.values.first;

      while ((angle - event.heading!).abs() > _angleThreshold) {
        // TODO : Send Bluetooth Signal with angle
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Color.fromRGBO(0, 47, 255, 1);
    final fillColor = _submitted ? borderColor : Colors.white;
    final textColor = _submitted ? Colors.white : borderColor;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth  = MediaQuery.of(context).size.width;

    if (_isEnterSplash) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 28,
                letterSpacing: 10,
              ),
              children: [
                TextSpan(
                  text: 'NAVI',
                  style: TextStyle(
                    color: Color.fromRGBO(0, 47, 255, 1),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: 'GATION\n',
                  style: TextStyle(color: Colors.grey),
                ),
                TextSpan(
                  text: 'VI',
                  style: TextStyle(color: Colors.grey),
                ),
                TextSpan(
                  text: 'BRATION',
                  style: TextStyle(
                    color: Color.fromRGBO(0, 47, 255, 1),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
        backgroundColor: Color.fromRGBO(250, 250, 250, 1),
        body: Stack(
          children: [
            // MapPage
            if (_showMap && _pathData?["linePoints"] != null && _pathData?["linePoints"] is List<LatLng>)
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
                              Text(APIService.selectedName, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),),
                              Text(APIService.selectedAddr, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),),
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
                                onPressed: () async {
                                  if (!_startNavi) {
                                    _startNavi = true;
                                    print("no_movement_notice");
                                    await playAudio("no_movement_notice.mp3", onComplete: () {
                                      () async {
                                        _startListeningToCompass();
                                        calculateAngleData();

                                        try {
                                          await Clipboard.setData(
                                              ClipboardData(text: getAngleString())
                                          );
                                        } catch (e, stackTrace) {
                                          String errorMessage = "❗️에러 발생: $e\n📍StackTrace:\n$stackTrace";
                                          print(errorMessage);

                                          await Clipboard.setData(
                                              ClipboardData(text: errorMessage)
                                          );

                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('내부 오류 발생. 에러메시지 복사됨.'),
                                              ),
                                            );
                                          }
                                        }

                                        _startNavigation();

                                        // 사용자 방향 조정하기

                                      }(); // async 함수 즉시 실행
                                    });

                                    // TODO : 안내 신호 보내기

                                    // Clipboard.setData(
                                    //     ClipboardData(text: getAngleString())
                                    // );
                                  }
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
                              if (_pathMode != value) {
                                setState(() {
                                  _pathMode = value!;
                                });
                              }
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
                                          final newValue = _pathCountList[index];
                                          if (_pathCount != newValue) {
                                            setState(() {
                                              _pathCount = newValue;
                                            });
                                          }
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
  static String selectedAddr = "";
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
                            selectedAddr = places[index].keys.first.split("|||").last;
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

    double totalKm;
    double totalHour;

    try {
      totalKm = features[0]["properties"]["totalDistance"] / 1000;
      totalHour = features[0]["properties"]["totalTime"] / 60;
    } catch (Exception) {
      totalKm = -1;
      totalHour = -1;
    }

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
