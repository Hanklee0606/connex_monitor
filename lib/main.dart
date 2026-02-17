import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connex Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BleService _bleService = BleService();

  bool _isConnected = false;
  bool _isScanning = false;

  // SpO2 + 脈搏
  int? _spo2;
  int? _pulseRate;

  // 血壓
  int? _systolic;
  int? _diastolic;
  int? _meanArterial;

  // 體溫
  double? _temperature;
  String _tempUnit = 'C';

  @override
  void initState() {
    super.initState();

    _bleService.connectionStream.listen((connected) {
      setState(() {
        _isConnected = connected;
        _isScanning = false;
        if (!connected) _clearData();
      });
    });

    _bleService.dataStream.listen((data) {
      setState(() {
        switch (data['type']) {
          case 'plx':
            _spo2 = data['spo2'];
            _pulseRate = data['pulseRate'];
            break;
          case 'bp':
            _systolic = data['systolic'];
            _diastolic = data['diastolic'];
            _meanArterial = data['meanArterial'];
            break;
          case 'temp':
            _temperature = data['temperature'];
            _tempUnit = data['unit'];
            break;
        }
      });
    });
  }

  void _clearData() {
    _spo2 = null;
    _pulseRate = null;
    _systolic = null;
    _diastolic = null;
    _meanArterial = null;
    _temperature = null;
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    setState(() => _isScanning = true);
    try {
      final devices = await _bleService.scanDevices();

      if (!mounted) return;
      setState(() => _isScanning = false);

      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('找不到 WACSM 設備，請確認設備已開機'),
            backgroundColor: Colors.orange.shade400,
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<BluetoothDevice>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '選擇設備',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '找到 ${devices.length} 台設備',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              ...devices.map((device) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bluetooth,
                        color: Color(0xFF2196F3),
                        size: 22,
                      ),
                    ),
                    title: Text(
                      device.platformName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      device.remoteId.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF2196F3),
                    ),
                    onTap: () => Navigator.pop(context, device),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (selected != null) {
        setState(() => _isScanning = true);
        await _bleService.connectToDevice(selected);
      }
    } catch (e) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('錯誤：$e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  Future<void> _handleDisconnect() async {
    await _bleService.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Connex Monitor',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 連線狀態
              _StatusCard(isConnected: _isConnected),
              const SizedBox(height: 20),

              // SpO2 + 脈搏
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'SpO₂',
                      value: _spo2?.toString() ?? '--',
                      unit: '%',
                      icon: Icons.air,
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _MetricCard(
                      label: '脈搏',
                      value: _pulseRate?.toString() ?? '--',
                      unit: 'bpm',
                      icon: Icons.favorite,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 血壓
              _BpCard(
                systolic: _systolic,
                diastolic: _diastolic,
                meanArterial: _meanArterial,
              ),
              const SizedBox(height: 16),

              // 體溫
              _MetricCard(
                label: '體溫',
                value: _temperature != null
                    ? _temperature!.toStringAsFixed(1)
                    : '--',
                unit: '°$_tempUnit',
                icon: Icons.thermostat,
                color: const Color(0xFFFF9800),
              ),
              const SizedBox(height: 32),

              // 按鈕
              _isConnected
                  ? OutlinedButton.icon(
                      onPressed: _handleDisconnect,
                      icon: const Icon(Icons.bluetooth_disabled),
                      label: const Text('斷開連線'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade400,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _isScanning ? null : _handleConnect,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.bluetooth_searching),
                      label: Text(_isScanning ? '掃描中...' : '掃描並連線'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              const SizedBox(height: 12),

              Text(
                _isConnected
                    ? '設備已連線，請在 Connex Spot Monitor 上進行測量'
                    : '請確保設備已開機並在藍牙範圍內',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 連線狀態卡片 ──────────────────────────────────
class _StatusCard extends StatelessWidget {
  final bool isConnected;
  const _StatusCard({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? const Color(0xFF4CAF50)
                  : Colors.grey.shade300,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isConnected ? '已連線' : '未連線',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: isConnected
                  ? const Color(0xFF4CAF50)
                  : Colors.grey.shade500,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.bluetooth,
            size: 20,
            color: isConnected
                ? const Color(0xFF2196F3)
                : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
}

// ── 單一數值卡片 ──────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasValue = value != '--';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w700,
              color: hasValue ? color : Colors.grey.shade300,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 血壓卡片 ──────────────────────────────────────
class _BpCard extends StatelessWidget {
  final int? systolic;
  final int? diastolic;
  final int? meanArterial;

  const _BpCard({
    required this.systolic,
    required this.diastolic,
    required this.meanArterial,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart,
                  size: 18, color: Color(0xFF9C27B0)),
              const SizedBox(width: 6),
              Text(
                '血壓',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Text(
                'mmHg',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _BpValue(
                label: '收縮壓',
                value: systolic?.toString() ?? '--',
                color: const Color(0xFF9C27B0),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.grey.shade200,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              _BpValue(
                label: '舒張壓',
                value: diastolic?.toString() ?? '--',
                color: const Color(0xFF7B1FA2),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.grey.shade200,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              _BpValue(
                label: '平均壓',
                value: meanArterial?.toString() ?? '--',
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BpValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BpValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasValue = value != '--';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: hasValue ? color : Colors.grey.shade300,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}