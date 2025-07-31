import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BLEChatPage extends StatefulWidget {
  @override
  _BLEChatPageState createState() => _BLEChatPageState();
}

class _BLEChatPageState extends State<BLEChatPage> {
  final flutterReactiveBle = FlutterReactiveBle();
  final Uuid serviceUuid = Uuid.parse("12345678-1234-5678-1234-56789abcdef0");
  final Uuid charUuid = Uuid.parse("abcdefab-1234-5678-1234-56789abcdef0");

  DiscoveredDevice? _targetDevice;
  QualifiedCharacteristic? _chatChar;
  String _log = '';
  final TextEditingController _controller = TextEditingController();

  void _startScan() {
    setState(() => _log = '🔍 Scanning...');
    flutterReactiveBle.scanForDevices(withServices: [serviceUuid]).listen((device) {
      if (device.name == 'PiChat') {
        setState(() {
          _targetDevice = device;
          _log = '✅ Found ${device.name}';
        });
        _connectToDevice(device);
      }
    });
  }

  void _connectToDevice(DiscoveredDevice device) async {
    await flutterReactiveBle.connectToDevice(id: device.id).listen((event) {
      if (event.connectionState == DeviceConnectionState.connected) {
        _log += '\n🔗 Connected!';
        _chatChar = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: charUuid,
          deviceId: device.id,
        );
        _listenForMessages();
      }
    });
  }

  void _sendMessage(String msg) async {
    if (_chatChar == null) return;
    await flutterReactiveBle.writeCharacteristicWithResponse(
      _chatChar!,
      value: msg.codeUnits,
    );
    setState(() => _log += '\n👤 Me: $msg');
    _controller.clear();
  }

  void _listenForMessages() {
    flutterReactiveBle.subscribeToCharacteristic(_chatChar!).listen((data) {
      setState(() {
        _log += '\n🤖 Pi: ${String.fromCharCodes(data)}';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('BLE Chat with Pi')),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: _startScan,
            child: Text('🔍 Scan and Connect'),
          ),
          Expanded(child: SingleChildScrollView(child: Text(_log))),
          Row(
            children: [
              Expanded(child: TextField(controller: _controller)),
              IconButton(
                icon: Icon(Icons.send),
                onPressed: () => _sendMessage(_controller.text),
              )
            ],
          )
        ],
      ),
    );
  }
}
