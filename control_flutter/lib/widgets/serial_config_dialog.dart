import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../api/serial.dart';

class SerialConfigDialog extends StatefulWidget {
  final SerialConfig initialConfig;
  final Function(SerialConfig) onConfigChanged;

  const SerialConfigDialog({
    super.key,
    required this.initialConfig,
    required this.onConfigChanged,
  });

  @override
  State<SerialConfigDialog> createState() => _SerialConfigDialogState();
}

class _SerialConfigDialogState extends State<SerialConfigDialog> {
  late SerialConfig _config;

  // 可选的波特率列表
  final List<int> _baudRates = [
    9600,
    19200,
    38400,
    57600,
    921600,
    230400,
    460800,
    921600,
  ];

  // 可选的数据位
  final List<int> _dataBits = [5, 6, 7, 8];

  // 可选的校验位 - 修改为使用整数常量
  final Map<String, int> _parityOptions = {
    '无校验': SerialPortParity.none,
    '奇校验': SerialPortParity.odd,
    '偶校验': SerialPortParity.even,
    '标志校验': SerialPortParity.mark,
    '空格校验': SerialPortParity.space,
  };

  // 可选的停止位
  final Map<String, int> _stopBitsOptions = {
    '1位': 1,
    '1.5位': 15, // 在SerialPortConfig中使用15表示1.5位
    '2位': 2,
  };

  // 可选的流控制 - 修改为使用整数常量
  final Map<String, int> _flowControlOptions = {
    '无': SerialPortFlowControl.none,
    '硬件RTS/CTS': SerialPortFlowControl.rtsCts,
    '硬件DTR/DSR': SerialPortFlowControl.dtrDsr,
    '软件XON/XOFF': SerialPortFlowControl.xonXoff,
  };

  @override
  void initState() {
    super.initState();
    // 复制初始配置，避免直接修改传入的对象
    _config = SerialConfig(
      portName: widget.initialConfig.portName,
      baudRate: widget.initialConfig.baudRate,
      dataBits: widget.initialConfig.dataBits,
      parity: widget.initialConfig.parity,
      stopBits: widget.initialConfig.stopBits,
      flowControl: widget.initialConfig.flowControl,
      timeoutMs: widget.initialConfig.timeoutMs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('串口配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 波特率设置
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '波特率'),
              value: _config.baudRate,
              items:
                  _baudRates.map((rate) {
                    return DropdownMenuItem<int>(
                      value: rate,
                      child: Text('$rate'),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config.baudRate = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // 数据位设置
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '数据位'),
              value: _config.dataBits,
              items:
                  _dataBits.map((bits) {
                    return DropdownMenuItem<int>(
                      value: bits,
                      child: Text('$bits'),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config.dataBits = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // 校验位设置 - 修改为使用整数类型
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '校验位'),
              value: _config.parity,
              items:
                  _parityOptions.entries.map((entry) {
                    return DropdownMenuItem<int>(
                      value: entry.value,
                      child: Text(entry.key),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config.parity = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // 停止位设置
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '停止位'),
              value: _config.stopBits,
              items:
                  _stopBitsOptions.entries.map((entry) {
                    return DropdownMenuItem<int>(
                      value: entry.value,
                      child: Text(entry.key),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config.stopBits = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // 流控制设置 - 修改为使用整数类型
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '流控制'),
              value: _config.flowControl,
              items:
                  _flowControlOptions.entries.map((entry) {
                    return DropdownMenuItem<int>(
                      value: entry.value,
                      child: Text(entry.key),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config.flowControl = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // 超时设置
            TextFormField(
              decoration: const InputDecoration(
                labelText: '超时 (毫秒)',
                hintText: '100-5000',
              ),
              keyboardType: TextInputType.number,
              initialValue: _config.timeoutMs.toString(),
              onChanged: (value) {
                final timeout = int.tryParse(value);
                if (timeout != null && timeout >= 100 && timeout <= 5000) {
                  setState(() {
                    _config.timeoutMs = timeout;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfigChanged(_config);
            Navigator.of(context).pop();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
