import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math' as math;

class CompassTestPage extends StatefulWidget {
  const CompassTestPage({super.key});

  @override
  State<CompassTestPage> createState() => _CompassTestPageState();
}

class _CompassTestPageState extends State<CompassTestPage> {
  double? _lastHeading;
  bool _isStable = false;
  Timer? _stabilityTimer;
  double _stabilityThreshold = 3;
  final int _stableDuration = 2;

  StreamSubscription<CompassEvent>? _compassSub;

  @override
  void initState() {
    super.initState();
    _startListeningToCompass();
  }

  void _startListeningToCompass() {
    print("_startListeningToCompass run");

    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen((event) {
      final currentHeading = event.heading;
      if (currentHeading == null) return;

      if (_lastHeading != null) {
        double delta = _angleDifference(currentHeading, _lastHeading!);

        print("🧭 현재: ${currentHeading.toStringAsFixed(2)}°, 이전: ${_lastHeading!.toStringAsFixed(2)}°, Δ: ${delta.toStringAsFixed(2)}°, isStable: ${_isStable.toString()}");

        if (delta < _stabilityThreshold) {
          _startStabilityTimer();
        } else {
          print("😵 흔들림 감지 → 안정화 리셋");
          _cancelStabilityTimer();
          _updateStableState(false);
        }
      }

      // 항상 최신값 유지
      _lastHeading = currentHeading;

      setState(() {});
    });
  }

  double _angleDifference(double a, double b) {
    double diff = (a - b).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  void _startStabilityTimer() {
    if (_stabilityTimer != null) return;

    _stabilityTimer = Timer(Duration(seconds: _stableDuration), () {
      print("✅ 방향 안정됨!");
      _updateStableState(true);
    });
  }

  void _cancelStabilityTimer() {
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
  }

  void _updateStableState(bool value) {
    if (_isStable != value) {
      setState(() {
        _isStable = value;
      });
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _stabilityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("나침반 테스트")),
      body: Center(
        child: _lastHeading == null
            ? const Text("센서를 찾을 수 없습니다")
            : Transform.rotate(
          angle: (_lastHeading! * (math.pi / 180) * -1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_lastHeading!.toStringAsFixed(1),
                  style: TextStyle(fontSize: 72)),
              Text(_isStable ? "안정됨 ✅" : "움직이는 중... 🌀",
                  style: TextStyle(fontSize: 32)),
            ],
          ),
        ),
      ),
    );
  }
}
