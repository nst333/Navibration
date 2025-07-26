import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math' as math;

class CompassTestPage extends StatefulWidget {
  const CompassTestPage({super.key});

  @override
  State<CompassTestPage> createState() => _CompassTestPageState();
}

class _CompassTestPageState extends State<CompassTestPage> {
  double? _direction;

  @override
  void initState() {
    super.initState();
    FlutterCompass.events?.listen((event) {
      setState(() {
        _direction = event.heading;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("나침반 테스트")),
      body: Center(
        child: _direction == null
            ? const Text("센서를 찾을 수 없습니다")
            : Transform.rotate(
          angle: ((_direction ?? 0) * (math.pi / 180) * -1),
          child: Text(_direction.toString(), style: TextStyle(fontSize: 72),)
        ),
      ),
    );
  }
}
