import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:navibration/blueTest.dart';
import 'package:navibration/dialogTest.dart';
import 'package:navibration/directionIndicator.dart';
import 'package:rxdart/rxdart.dart';

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

const double _deg2rad = pi / 180;
const double _rad2deg = 180 / pi;
@pragma('vm:prefer-inline')
double _d2r(double deg) => deg * _deg2rad;
double _r2d(double rad) => rad * _rad2deg;

void main() {
  runApp(
    MaterialApp(
      home: MainApp(),
      //home: DialogTest(),
      //home: Directionindicator(),
      //home: BLEChatPage(),
    ),
  );
}

//void main() => runApp(MainApp());
//void main() => runApp(MapPage());
//void main() => runApp(SearchMapPage());

class MainApp extends StatefulWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  late AnimationController _slideAnimController;
  late Animation<Offset> _slideAnim;
  bool isMenuOpen = false;

  bool _submitted = false;
  bool _focused = false;
  bool _isEnterSplash = true;
  Map<String, dynamic>? _pathData;
  Map<LatLng, double> _angleData = {};

  static const _animDuration = Duration(milliseconds: 500);

  bool _isAvoidStairMode = false;

  int _pathCount = 10;
  late LatLng _currentPos;

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

    // Future.delayed(Duration(seconds: 2), () {
    //   if (mounted) {
    //     setState(() {
    //       _isEnterSplash = false;
    //     });
    //   }
    // });

    _controller.addListener(() {
      if (_controller.text.isEmpty && _submitted) {
        if (mounted) {
          setState(() {
            _submitted = false;
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

    _slideAnimController = AnimationController(
      vsync: this,
      duration: _animDuration,
    );

    _slideAnim = Tween<Offset>(begin: Offset(-1, 0), end: Offset(0, 0)).animate(
      CurvedAnimation(
        parent: _slideAnimController,
        curve: Curves.easeInOutQuint,
      ),
    );
  }

  void toggleMenu() {
    setState(() {
      if (isMenuOpen) {
        _slideAnimController.reverse();
      } else {
        _slideAnimController.forward();
      }
      isMenuOpen = !isMenuOpen;
    });
  }

  Future<void> _onSearchSubmitted(String keyword) async {
    String value = _controller.text;
    if (value.isNotEmpty) {
      final places = await APIService.findLatLngByName(value, _pathCount);
      if (places.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('장소를 찾을 수 없습니다.')));
        _controller.clear();
        return;
      }

      playAudio("select_destination.mp3"); // 목적지를 선택하세요

      APIService.showDestinationDialog(
        context,
        places,
        (name, pos) => _handleSelectedDestination(name, pos),
      );
    } else {
      setState(() {
        _submitted = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _slideAnimController.dispose();
    _compassSub?.cancel();
    super.dispose();
  }

  Future<void> _handleSelectedDestination(String name, LatLng pos) async {
    _player.stop();

    debugPrint("enter _handleSelectedDestination");
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint("serviceEnabled declared");
    if (!serviceEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('위치 서비스가 비활성화되어 있습니다.')));
      return;
    }

    permission = await Geolocator.checkPermission();
    print("check permission");
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      print("request permission");
      if (permission == LocationPermission.denied) {
        print("denied permission");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('위치 권한이 거부되었습니다.')));
        return;
      }
    }

    print("check forever denied permission");
    if (permission == LocationPermission.deniedForever) {
      print("forever denied permission");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('위치 권한이 영구적으로 거부되었습니다.')));
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    _currentPos = LatLng(position.latitude, position.longitude);
    debugPrint("got position : ${position.latitude} | ${position.longitude}");

    final routeData = await APIService.fetchPedestrianRoute(
      startLat: position.latitude,
      startLng: position.longitude,

      endLat: APIService.selectedPos.latitude,
      endLng: APIService.selectedPos.longitude,

      pathMode: _isAvoidStairMode ? "0" : "30",
    );

    if (routeData != [] &&
        routeData?["linePoints"] != null &&
        routeData?["linePoints"] is List<LatLng>) {
      _pathData = routeData;

      setState(() {
        _submitted = true;
      });
      _focusNode.unfocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("경로를 계산할 수 없습니다.\n인터넷이 연결되었는지 확인해주세요.")),
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
            side: BorderSide(color: Color.fromRGBO(0, 47, 255, 1), width: 2),
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

  // void _startListeningToCompass() {
  //   print("_startListeningToCompass run");
  //
  //   _compassSub?.cancel();
  //   _compassSub = FlutterCompass.events?.listen((event) async {
  //     final currentHeading = event.heading;
  //     if (currentHeading == null) return;
  //
  //     if (_lastHeading != null) {
  //       double delta = _angleDifference(currentHeading, _lastHeading!);
  //
  //       if (!_headingConfirmed) {
  //         if (delta < _stabilityThreshold) {
  //           _stableTicks++;
  //
  //           if (_stableTicks == 1) {
  //             _showDirectionPopup("📡 방향 안정화 중입니다...\n핸드폰을 고정해 주세요.");
  //           }
  //
  //           if (_stableTicks >= _requiredStableTicks) {
  //             // debugPrint("🧭 방향 안정화 확정 (연속 $_requiredStableTicks 프레임)");
  //             // _headingConfirmed = true;
  //             // await _speakAndConfirm(currentHeading);
  //
  //             debugPrint("🧭 방향 안정화 확정됨");
  //             _headingConfirmed = true;
  //
  //             _showDirectionPopup("🧭 방향 안정화 확정됨");
  //             await Future.delayed(Duration(seconds: 1)); // 완료 메시지 보여주기
  //
  //             _hideDirectionPopup();
  //             await _speakAndConfirm(currentHeading);
  //           }
  //         } else {
  //           if (_stableTicks > 0) {
  //             debugPrint("🌀 방향 흔들림 감지됨. 안정 카운트 초기화");
  //           }
  //           _stableTicks = 0;
  //         }
  //       }
  //     }
  //
  //     _lastHeading = currentHeading;
  //     setState(() {});
  //   });
  // }
  void _startListeningToCompass() {
    _compassSub?.cancel();

    _compassSub = FlutterCompass.events
        ?.where((e) => e.heading != null)
        .throttleTime(const Duration(milliseconds: 20))
        .distinct((p, n) => _angleDifference(p.heading!, n.heading!) < 1)
        .listen(_handleCompassEvent);
  }

  void _handleCompassEvent(CompassEvent event) async {
    final currentHeading = event.heading!;
    if (_lastHeading != null) {
      final delta = _angleDifference(currentHeading, _lastHeading!);

      if (!_headingConfirmed) {
        if (delta < _stabilityThreshold) {
          _stableTicks++;

          if (_stableTicks == 1) {
            _showDirectionPopup("📡 방향 안정화 중입니다...\n핸드폰을 고정해 주세요.");
          }

          if (_stableTicks >= _requiredStableTicks) {
            debugPrint("🧭 방향 안정화 확정됨");
            _headingConfirmed = true;

            _showDirectionPopup("🧭 방향 안정화 확정됨");
            await Future.delayed(const Duration(seconds: 1));
            _hideDirectionPopup();

            await _speakAndConfirm(currentHeading);
          }
        } else {
          if (_stableTicks > 0) debugPrint("🌀 흔들림 감지 → 카운트 초기화");
          _stableTicks = 0;
        }
      }
    }

    _lastHeading = currentHeading;
    if (mounted) setState(() {}); // UI 갱신
  }

  Future<void> _setStartDirection(double heading) async {
    debugPrint("🧭 설정 완료! 시작 방향은 $heading 도");

    _finalHeading = heading;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("🧭 설정 완료! 시작 방향은 $heading 도")));
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
      _angleData[points[i - 1]] = calculateBearing(points[i - 1], points[i]);
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

    double phi1 = _d2r(a.latitude);
    double phi2 = _d2r(b.latitude);
    double lambda1 = _d2r(a.longitude);
    double lambda2 = _d2r(b.longitude);

    return _toRelativeAngle(
      _r2d(
        atan2(
          sin(lambda2 - lambda1) * cos(phi2),

          cos(phi1) * sin(phi2) -
              sin(phi1) * cos(phi2) * cos(lambda2 - lambda1),
        ),
      ),
    );
  }

  double calculateHarverSine(LatLng a, LatLng b) {
    // HaverSine Formula
    // θ = d/r
    // hav(θ) = hav(Δφ) + cos(φ1)cos(φ2)hav(Δλ)
    //        = sin^2(θ/2) = (1-cos(θ)/2
    // d = r * archav(h) = 2r * arcsin(sqrt(h))
    //   = 2r * arcsin(sqrt(hav(Δφ) + cos(φ1)cos(φ2)hav(Δλ)
    //   = 2r * arcsin(sqrt(sin^2(Δφ/2) + cos(φ1)cos(φ2)sin^2(Δλ/2)))

    double lat1 = _d2r(a.latitude);
    double lat2 = _d2r(b.latitude);

    double lon1 = _d2r(a.longitude);
    double lon2 = _d2r(b.longitude);

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    return 2 *
        earthRadius *
        asin(
          sqrt(
            pow(sin(dLat / 2), 2) +
                cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2),
          ),
        );
  }

  String getAngleString() {
    String result = '';

    for (var entry in _angleData.entries) {
      result +=
          '${entry.key.toString()}  ----->  ${entry.value.toStringAsFixed(2)}\n';
    }

    return result;
  }

  Future<Map<String, double>> calculateVibrationType(LatLng target) async {
    // 사용자 위치랑 매개변수 위치
    Position currentPos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );

    double angle = calculateBearing(
      LatLng(currentPos.latitude, currentPos.longitude),
      target,
    );

    String type = "";
    if (angle >= _angleThreshold && angle < 180 - _angleThreshold) {
      type = "R";
    } else if (angle > 180 + _angleThreshold && angle < 360 - _angleThreshold) {
      type = "L";
    } else if (angle >= 180 - _angleThreshold &&
        angle <= 180 + _angleThreshold) {
      type = "U";
    } else {
      type = "S";
    }

    return {type: angle};
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
    final posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );

    _compassSub?.cancel();
    _compassSub =
        Rx.combineLatest2(
                  posStream,
                  FlutterCompass.events!,
                  (Position p, CompassEvent c) => (p, c.heading),
                )
                .sampleTime(const Duration(milliseconds: 100)) // 10Hz 샘플
                .listen((tuple) async {
                  final (Position p, double? heading) = tuple;
                  if (heading == null) return;

                  final nextCorner = _getNearestCorner(
                    LatLng(p.latitude, p.longitude),
                  );
                  if (nextCorner == null) return;

                  final vibrationInfo = await calculateVibrationType(
                    nextCorner,
                  );
                  final angle = vibrationInfo.values.first;

                  if ((angle - heading).abs() > _angleThreshold) {
                    // TODO : 블루투스에 angle & 패턴 전송
                  } else if ((angle - heading).abs() > 50) {
                    // TODO : 경로 이탈 처리
                  }
                })
            as StreamSubscription<CompassEvent>?;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Color.fromRGBO(0, 47, 255, 1);
    final fillColor = _submitted ? borderColor : Colors.white;
    final textColor = _submitted ? Colors.white : borderColor;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    if (_isEnterSplash) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 28, letterSpacing: 10),
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
          if (_submitted &&
              _pathData?["linePoints"] != null &&
              _pathData?["linePoints"] is List<LatLng>)
            AnimatedOpacity(
              duration: Duration(
                milliseconds: _animDuration.inMilliseconds + 200,
              ),
              opacity: _submitted ? 1 : 0,
              child: MapPage(
                routePoints: _pathData?["linePoints"] ?? [],
                startPoint: _pathData?['startPoint'] ?? LatLng(0, 0),
                endPoint: _pathData?['endPoint'] ?? LatLng(0, 0),
                currentPos: _currentPos,
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
                    bottom: _submitted
                        ? (screenHeight / 2) + (screenHeight * (20 / 100))
                        : 0,
                  ),
                  duration: _animDuration,
                  curve: Curves.easeInOutQuint,
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
                          ),
                        ],
                      ),

                      child: TextField(
                        // 이거 버튼이 되어야 한다. -> 음성인식 열리고 안내하기 (단점. 사용자가 그냥 목적지만 말하지 않음)
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
                              Icon(Icons.search, color: textColor, size: 40),
                              Text(
                                "장소 검색",
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 25,
                                ),
                              ),
                            ],
                          ),
                          filled: true,
                          fillColor: fillColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: borderColor,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Color.fromRGBO(0, 58, 255, 1),
                              width: 1.5,
                            ),
                          ),
                        ),
                        onSubmitted: _onSearchSubmitted,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 30),

                Center(
                  child: Column(
                    children: [
                      Switch(
                        value: _isAvoidStairMode,
                        onChanged: (value) {
                          setState(() {
                            _isAvoidStairMode = value;
                          });
                        },
                        activeColor: borderColor,
                        inactiveThumbColor: Colors.grey,
                      ),

                      Text(
                        _isAvoidStairMode ? "계단 회피" : "기본",
                        style: TextStyle(
                            color: _isAvoidStairMode ? textColor : Colors.grey,
                            fontSize: 24,
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
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
            bottom: _submitted
                ? 0
                : -(screenHeight * (30 / 100)), // 보이지 않도록 화면 아래에 두기
            height: (screenHeight * (30 / 100)),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 텍스트 영역
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AutoSizeText(
                              APIService.selectedName,
                              maxLines: 1,
                              minFontSize: 12,
                              stepGranularity: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AutoSizeText(
                              APIService.selectedAddr,
                              maxLines: 2,
                              minFontSize: 10,
                              stepGranularity: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 20),

                      // 시작 버튼
                      ElevatedButton(
                        child: Text(
                          '시작',
                          style: TextStyle(color: borderColor),
                        ),
                        onPressed: () async {
                          if (!_startNavi) {
                            _startNavi = true;
                            print("no_movement_notice");

                            await playAudio(
                            "no_movement_notice.mp3",
                            onComplete: () {
                              () async {
                                _startListeningToCompass();
                                calculateAngleData();

                                try {
                                  await Clipboard.setData(
                                    ClipboardData(text: getAngleString()),
                                  );
                                } catch (e, stackTrace) {
                                  String errorMessage =
                                      "❗️에러 발생: $e\n📍StackTrace:\n$stackTrace";
                                  print(errorMessage);

                                  await Clipboard.setData(
                                    ClipboardData(text: errorMessage),
                                  );

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text('내부 오류 발생. 에러메시지 복사됨.'),
                                      ),
                                    );
                                  }
                                }

                                _startNavigation();
                              }(); // 즉시 실행 async
                            },
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
    void Function(String name, LatLng pos) onPlaceSelected,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: Duration(milliseconds: 700),
      pageBuilder: (_, __, ___) {
        return SizedBox();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutQuint,
          ),
          child: Container(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: places.length,
                      separatorBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 0),
                        child: Divider(color: Colors.grey, thickness: 1),
                      ),
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            selectedName = places[index].keys.first
                                .split("|||")
                                .first;
                            selectedAddr = places[index].keys.first
                                .split("|||")
                                .last;
                            selectedPos = places[index].values.first;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('목적지 선택 완료!\n$selectedName'),
                              ),
                            );

                            Navigator.of(context).pop();
                            onPlaceSelected(selectedName, selectedPos);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  places[index].keys.first.split("|||").first,
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  places[index].keys.first.split("|||").last,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.black
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  SizedBox(height: 8),

                  IconButton(
                    icon: Icon(Icons.close, size: 36),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 키워드로 POI를 검색해 [이름, 주소, 위도, 경도] 맵의 리스트를 반환
  static Future<List<Map<String, LatLng>>> findLatLngByName(
    String keyword,
    int count,
  ) async {
    if (keyword.isEmpty) return [];

    final uri = Uri.https('apis.openapi.sk.com', '/tmap/pois', {
      'version': '1',
      'format': 'json',
      'searchKeyword': keyword,
      'resCoordType': 'WGS84GEO',
      'count': count.toString(),
    });

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
        String key =
            poi["name"] +
            "|||" +
            (poi["upperAddrName"] +
                " " +
                poi["middleAddrName"] +
                " " +
                poi["lowerAddrName"]);
        LatLng value = LatLng(
          double.parse(poi["pnsLat"]),
          double.parse(poi["pnsLon"]),
        );

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
    required String pathMode,
  }) async {
    final uri = Uri.https('apis.openapi.sk.com', '/tmap/routes/pedestrian', {
      'version': '1',
      'format': 'json',
    });

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'appKey': _appKey,
      },
      body: {
        'startX': '$startLng',
        'startY': '$startLat',
        'endX': '$endLng',
        'endY': '$endLat',
        'searchOption': pathMode,
        'reqCoordType': 'WGS84GEO',
        'startName': '출발지',
        'endName': '도착지',
      },
    );

    if (response.statusCode != 200) return null;

    // ★ UI 스레드 끊김 방지를 위해 compute 사용
    final data = await compute(jsonDecode, response.body);

    final features = data["features"];
    if (features == null) return null;

    Clipboard.setData(ClipboardData(text: features.toString()));

    final List<String> descriptions = [];
    final List<LatLng> linePoints = [];

    /*
    <도로 타입 코드(상세 위치 구분)>
    - 21: 보행자도로 1 (차도와 인도가 분리되어 있으며 정해진 횡단구역으로만 횡단 가능한 보행자 도로 )
    - 22: 보행자도로 2 (차도와 인도가 분리되어 있지 않거나, 보행자 횡단에 제약이 없는 보행자도로 )
    - 23: 보행자도로 3 (차량 통행이 불가능한 보행자도로 )
    - 24: 보행자도로 4 (쾌적하지 않은 도로 )
     */
    final List<int> roadTypes = [];

    double totalKm = -1, totalHour = -1;
    try {
      totalKm = features[0]["properties"]["totalDistance"] / 1000;
      totalHour = features[0]["properties"]["totalTime"] / 60;
    } catch (_) {}

    for (final f in features) {
      switch (f["geometry"]["type"]) {
        case "Point":
          linePoints.add(
            LatLng(
              f["geometry"]["coordinates"][1],
              f["geometry"]["coordinates"][0],
            ),
          );
          break;
        case "LineString":
          descriptions.add(f["properties"]["description"]);

          roadTypes.add(f["properties"]["roadType"]);
          break;
      }
    }

    return {
      'startPoint': LatLng(startLat, startLng),
      'endPoint': LatLng(endLat, endLng),
      'totalKm': totalKm,
      'totalHour': totalHour,
      'descriptions': descriptions,
      'linePoints': linePoints,
      'roadTypes': roadTypes,
    };
  }
}
