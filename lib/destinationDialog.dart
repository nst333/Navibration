import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class _DestinationDialogContent extends StatefulWidget {
  final List<Map<String, LatLng>> places;
  final void Function(String name, LatLng pos) onPlaceSelected;
  String selectedName;
  String selectedAddr;
  LatLng selectedPos;

  _DestinationDialogContent(
      {
        super.key,
        required this.places,
        required this.onPlaceSelected,
        required this.selectedName,
        required this.selectedAddr,
        required this.selectedPos
      });

  @override
  State<_DestinationDialogContent> createState() => _DestinationDialogContentState();
}

class _DestinationDialogContentState extends State<_DestinationDialogContent> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _opacity = 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Color.fromRGBO(0, 47, 255, 1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedOpacity(
          duration: Duration(milliseconds: 600),
          opacity: _opacity,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            margin: EdgeInsets.all(24),
            padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(width: 2, color: borderColor),
            ),
            child: Column(
              children: [
                Text(
                  '목적지를 선택하세요',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.places.length,
                    separatorBuilder: (_, __) => Divider(),
                    itemBuilder: (context, index) {
                      final name = widget.places[index].keys.first.split("|||").first;
                      final addr = widget.places[index].keys.first.split("|||").last;
                      final pos = widget.places[index].values.first;

                      return GestureDetector(
                        onTap: () {
                          widget.selectedName = name;
                          widget.selectedAddr = addr;
                          widget.selectedPos = pos;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('목적지 선택 완료!\n$name')),
                          );

                          Navigator.pop(context);
                          widget.onPlaceSelected(name, pos);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text(addr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w300)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
