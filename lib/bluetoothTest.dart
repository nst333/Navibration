import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

/// 1. 스캔 → 2. Pi 찾으면 stopDiscovery → 3. RFCOMM 연결 → 4. I/O 스트림 관리
class PiBluetoothService {
  static const _piName = 'NavibrationPi';     // <- 라즈파이 advertise 이름
  static const _lineEnding = '\n';            // 프로토콜 구분용

  final _bt = FlutterBluetoothSerial.instance;
  BluetoothConnection? _conn;
  StreamSubscription<BluetoothDiscoveryResult>? _scanSub;

  /// 연결 상태 change 콜백용
  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  // ───────────── public API ─────────────
  Future<void> init() async {
    if (!await _ensurePermissions()) {
      throw 'Bluetooth 권한이 거부되었습니다.';
    }
    if (await _bt.state != BluetoothState.STATE_ON) {
      await _bt.requestEnable();
    }
  }

  Future<void> scanAndConnect({Duration timeout = const Duration(seconds: 10)}) async {
    await disconnect();            // 혹시 이전 연결 남아 있으면 정리
    final completer = Completer<void>();

    _scanSub = _bt.startDiscovery().listen((result) async {
      if (result.device.name == _piName) {
        debugPrint('🔍 Pi 발견: ${result.device.address}');
        _scanSub?.cancel();

        try {
          _conn = await BluetoothConnection.toAddress(result.device.address);
          isConnected.value = true;
          debugPrint('✔ Pi 연결 성공');

          // 수신 스트림 예시 (선택)
          _conn!.input?.listen(_onPiData, onDone: () {
            debugPrint('⛔ Pi 연결 끊김');
            isConnected.value = false;
          });

          completer.complete();
        } catch (e) {
          completer.completeError('Pi 연결 실패: $e');
        }
      }
    });

    // 타임아웃 대비
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        _scanSub?.cancel();
        completer.completeError('타임아웃: Pi를 찾지 못했습니다.');
      }
    });

    return completer.future;
  }

  Future<void> send(String msg) async {
    if (_conn == null || !_conn!.isConnected) {
      throw '연결되지 않았습니다.';
    }
    _conn!.output.add(ascii.encode('$msg$_lineEnding'));
    await _conn!.output.allSent;
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _conn?.close();
    _conn = null;
    isConnected.value = false;
  }

  void dispose() => disconnect();

  // ───────────── private ─────────────
  void _onPiData(Uint8List data) {
    final s = ascii.decode(data).trim();
    debugPrint('Pi → 앱: $s');
    // 필요하면 패턴 매칭 후 추가 로직
  }

  Future<bool> _ensurePermissions() async {
    // Android 12+: CONNECT & SCAN, 이하 버전: LOCATION
    final req = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location, // <= Android 11 이하에서 still required
    ].request();

    return req.values.every((status) => status.isGranted);
  }
}
