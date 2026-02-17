import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String deviceNamePrefix = 'WACSM';

  // Service UUIDs
  static const String plxServiceUuid = '1822';
  static const String bpServiceUuid = '1810';
  static const String tempServiceUuid = '1809';

  // Characteristic UUIDs
  static const String plxCharUuid = '2a5e';
  static const String bpCharUuid = '2a35';
  static const String tempCharUuid = '2a1c';

  BluetoothDevice? _connectedDevice;
  final List<StreamSubscription> _subscriptions = [];

  final StreamController<Map<String, dynamic>> _dataController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  /// 掃描並回傳找到的設備清單
  Future<List<BluetoothDevice>> scanDevices() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      throw Exception('請先開啟藍牙');
    }

    List<BluetoothDevice> found = [];

    // 監聽掃描結果
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName.startsWith(deviceNamePrefix)) {
          if (!found.any((d) => d.remoteId == r.device.remoteId)) {
            found.add(r.device);
          }
        }
      }
    });

    // 開始掃描，10 秒後自動停止
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // 等掃描真正停止
    await FlutterBluePlus.isScanning.where((val) => val == false).first;

    await subscription.cancel();

    return found;
  }

  /// 連線到使用者選擇的設備
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      _connectedDevice = device;
      _connectionController.add(true);

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _connectionController.add(false);
          _cancelSubscriptions();
        }
      });

      await _discoverAndSubscribe(device);
    } catch (e) {
      _connectionController.add(false);
      rethrow;
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();

    for (BluetoothService service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();

      for (BluetoothCharacteristic char in service.characteristics) {
        final charUuid = char.uuid.toString().toLowerCase();

        // SpO2 + 脈搏
        if (serviceUuid.contains(plxServiceUuid) &&
            charUuid.contains(plxCharUuid)) {
          await _subscribe(char, _parsePlx);
        }

        // 血壓
        if (serviceUuid.contains(bpServiceUuid) &&
            charUuid.contains(bpCharUuid)) {
          await _subscribe(char, _parseBp);
        }

        // 體溫
        if (serviceUuid.contains(tempServiceUuid) &&
            charUuid.contains(tempCharUuid)) {
          await _subscribe(char, _parseTemp);
        }
      }
    }
  }

  Future<void> _subscribe(
    BluetoothCharacteristic char,
    Map<String, dynamic>? Function(List<int>) parser,
  ) async {
    await char.setNotifyValue(true);
    final sub = char.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        final parsed = parser(value);
        if (parsed != null) {
          _dataController.add(parsed);
        }
      }
    });
    _subscriptions.add(sub);
  }

  // ── 解析 SpO2 + 脈搏 ──────────────────────────────
  Map<String, dynamic>? _parsePlx(List<int> bytes) {
    if (bytes.length < 5) return null;
    final spo2 = bytes[1] | (bytes[2] << 8);
    final pulseRate = bytes[3] | (bytes[4] << 8);
    return {
      'type': 'plx',
      'spo2': spo2,
      'pulseRate': pulseRate,
    };
  }

  // ── 解析血壓 ──────────────────────────────────────
  Map<String, dynamic>? _parseBp(List<int> bytes) {
    if (bytes.length < 7) return null;
    final systolic = _sfloatToDouble(bytes[1], bytes[2]);
    final diastolic = _sfloatToDouble(bytes[3], bytes[4]);
    final meanArterial = _sfloatToDouble(bytes[5], bytes[6]);
    return {
      'type': 'bp',
      'systolic': systolic.round(),
      'diastolic': diastolic.round(),
      'meanArterial': meanArterial.round(),
    };
  }

  // ── 解析體溫 ──────────────────────────────────────
  Map<String, dynamic>? _parseTemp(List<int> bytes) {
    if (bytes.length < 5) return null;
    final flags = bytes[0];
    final isFahrenheit = (flags & 0x01) != 0;
    final temp = _ieee11073ToDouble(bytes[1], bytes[2], bytes[3], bytes[4]);
    return {
      'type': 'temp',
      'temperature': temp,
      'unit': isFahrenheit ? 'F' : 'C',
    };
  }

  // ── SFLOAT 轉換（血壓用）─────────────────────────
  double _sfloatToDouble(int lsb, int msb) {
    int raw = lsb | (msb << 8);
    int mantissa = raw & 0x0FFF;
    int exponent = raw >> 12;
    if (exponent >= 8) exponent -= 16;
    if (mantissa >= 0x800) mantissa -= 0x1000;
    return mantissa * _pow10(exponent);
  }

  // ── IEEE-11073 FLOAT 轉換（體溫用）──────────────
  double _ieee11073ToDouble(int b0, int b1, int b2, int b3) {
    int raw = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    int exponent = raw >> 24;
    int mantissa = raw & 0x00FFFFFF;
    if (exponent >= 0x80) exponent -= 0x100;
    if (mantissa >= 0x800000) mantissa -= 0x1000000;
    return mantissa * _pow10(exponent);
  }

  double _pow10(int exp) {
    if (exp == 0) return 1.0;
    if (exp > 0) {
      double result = 1.0;
      for (int i = 0; i < exp; i++) result *= 10;
      return result;
    } else {
      double result = 1.0;
      for (int i = 0; i < -exp; i++) result /= 10;
      return result;
    }
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> disconnect() async {
    _cancelSubscriptions();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _connectionController.add(false);
  }

  void dispose() {
    _cancelSubscriptions();
    _dataController.close();
    _connectionController.close();
  }
}