import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BleScanner extends StatefulWidget {
  const BleScanner({super.key});

  @override
  State<BleScanner> createState() => _BleScannerState();
}

class _BleScannerState extends State<BleScanner> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  late Stream<DiscoveredDevice> _scanStream;
  final List<DiscoveredDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    // 📛 권한 요청
    if (await Permission.location.request().isGranted &&
        await Permission.bluetoothScan.request().isGranted) {
      _scanStream = _ble.scanForDevices(
        withServices: [], // <-- 모든 BLE 장치 탐색
        scanMode: ScanMode.lowLatency,
      );

      _scanStream.listen((device) {
        if (_devices.indexWhere((d) => d.id == device.id) == -1) {
          setState(() {
            _devices.add(device);
          });
        }
      }, onError: (error) {
        print('스캔 중 오류 발생: $error');
      });
    } else {
      print('블루투스 또는 위치 권한이 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE 스캐너")),
      body: ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return ListTile(
            title: Text(device.name.isNotEmpty ? device.name : '(이름 없음)'),
            subtitle: Text(device.id),
            trailing: Text("${device.rssi} dBm"),
          );
        },
      ),
    );
  }
}
