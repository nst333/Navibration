import 'package:flutter/material.dart';

class DialogTest extends StatefulWidget {
  const DialogTest({super.key});

  @override
  State<DialogTest> createState() => _DialogTestState();
}

class _DialogTestState extends State<DialogTest> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  final items = List.generate(20, (index) => {"Item ${index + 1}"});

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _showCustomDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dialog",
      barrierColor: Colors.black54,
      transitionDuration: Duration(milliseconds: 500),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SizedBox(); // 실제 위젯은 transitionBuilder에서 리턴됨
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutQuint,
        );

        return ScaleTransition(
          scale: curvedAnimation,
          child: Center(
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      "목록 선택",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: 30,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: Icon(Icons.place),
                            title: Text("장소 $index"),
                            onTap: () {
                              Navigator.pop(context, index);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red,
      body: Center(
        child: ElevatedButton(
          child: const Text("누르다"),
          onPressed: _showCustomDialog,
        ),
      ),
    );
  }
}
