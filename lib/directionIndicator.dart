import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

class Directionindicator extends StatefulWidget {
  const Directionindicator({super.key});

  @override
  State<Directionindicator> createState() => _DirectionindicatorState();
}

class _DirectionindicatorState extends State<Directionindicator> {
  double? _heading;

  @override
  void initState() {
    super.initState();
    FlutterCompass.events?.listen((event) {
      setState(() {
        _heading = event.heading;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SizedBox(width: 16,),
                Icon(Icons.turn_left, size: 72, color: Colors.grey,),
                SizedBox(width: 72,),
                Icon(Icons.turn_right, size: 72, color: Colors.grey,),
                SizedBox(width: 16,),
              ],
            ),

            Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  _heading == null
                      ? "로딩 중..."
                      : "현재 각도: ${_heading!.toStringAsFixed(2)}°",
                  style: TextStyle(fontSize: 24),
                ),

                Transform.rotate(
                  angle: _heading!,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 128,
                  ),
                )
              ],
            ),

            Icon(Icons.u_turn_left, size: 72, color: Colors.grey,)
          ],
        ),
      )
    );
  }
}
