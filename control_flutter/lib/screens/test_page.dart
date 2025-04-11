import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../widgets/serial_config_dialog.dart';
import '../api/serial.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key, required this.title});

  final String title;

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  // 串口通信相关
  List<String> _availablePorts = [];
  String? _selectedPort;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  SerialConfig _serialConfig = SerialConfig.defaultConfig();

  // 接收/发送数据相关
  final TextEditingController _sendDataController = TextEditingController();
  final TextEditingController _hexDataController = TextEditingController();
  final List<String> _receivedData = [];
  bool _showAsHex = false;
  final int _maxBufferLines = 100;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  @override
  void dispose() {
    _stopSerial();
    _sendDataController.dispose();
    _hexDataController.dispose();
    super.dispose();
  }

  // 刷新可用串口列表
  Future<void> _refreshPorts() async {
    try {
      final portsResult = await SerialPort.availablePorts;
      final uniquePorts = portsResult.toSet().toList();
      final ports = uniquePorts.toList();

      if (mounted) {
        setState(() {
          _availablePorts = ports;

          // 如果当前选择的端口不在列表中，则重置选择
          if (_selectedPort != null &&
              !_availablePorts.contains(_selectedPort)) {
            _selectedPort =
                _availablePorts.isNotEmpty ? _availablePorts.first : null;
          } else if (_selectedPort == null && _availablePorts.isNotEmpty) {
            _selectedPort = _availablePorts.first;
          }

          // 更新串口配置中的端口名
          if (_selectedPort != null) {
            _serialConfig.portName = _selectedPort!;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showError('刷新串口列表失败: $e');
      }
    }
  }

  // 显示串口配置对话框
  void _showSerialConfigDialog() {
    showDialog(
      context: context,
      builder:
          (context) => SerialConfigDialog(
            initialConfig: _serialConfig,
            onConfigChanged: (config) {
              setState(() {
                _serialConfig = config;

                // 如果当前已连接，需要重新连接
                if (_isConnected) {
                  _reconnectWithNewConfig();
                }
              });
            },
          ),
    );
  }

  // 使用新配置重新连接
  Future<void> _reconnectWithNewConfig() async {
    // 先断开当前连接
    await _stopSerial();

    // 短暂延迟确保断开完成
    await Future.delayed(const Duration(milliseconds: 50));

    // 使用新配置重新连接
    await _startSerial();
  }

  // 开始串口连接
  Future<void> _startSerial() async {
    if (_selectedPort == null) {
      _showError('请选择串口');
      return;
    }

    if (mounted) {
      setState(() {
        _isConnecting = true;
        _serialConfig.portName = _selectedPort!;
      });
    }

    try {
      // 创建串口对象
      _port = SerialPort(_selectedPort!);

      // 打开串口
      if (!await _port!.openReadWrite()) {
        throw '无法打开串口进行读写操作';
      }

      // 配置串口
      final config = SerialPortConfig();
      config.baudRate = _serialConfig.baudRate;
      config.bits = _serialConfig.dataBits;
      config.parity = _serialConfig.parity;
      config.stopBits = _serialConfig.stopBits;
      config.setFlowControl(_serialConfig.flowControl);

      // 应用配置
      await _port!.setConfig(config);

      // 创建读取器并订阅数据
      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen(
        _onDataReceived,
        onError: (error) {
          if (mounted) {
            _showError('数据接收错误: $error');
            _stopSerial();
          }
        },
      );

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _receivedData.clear();
        });
        _addToReceivedData(
          '连接到 $_selectedPort 成功 (波特率: ${_serialConfig.baudRate})',
          isStatus: true,
        );
      }
    } catch (e) {
      if (_port != null) {
        if (_port!.isOpen) {
          await _port!.close();
        }
        _port!.dispose();
        _port = null;
      }

      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
        _showError('连接失败: $e');
      }
    }
  }

  // 停止串口连接
  Future<void> _stopSerial() async {
    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }

    if (_reader != null) {
      _reader = null;
    }

    if (_port != null) {
      if (_port!.isOpen) {
        await _port!.close();
      }
      _port!.dispose();
      _port = null;
    }

    if (mounted) {
      setState(() {
        _isConnected = false;
      });
      _addToReceivedData('串口连接已关闭', isStatus: true);
    }
  }

  // 连接/断开串口
  Future<void> _toggleConnection() async {
    if (_isConnected) {
      await _stopSerial();
    } else {
      await _startSerial();
    }
  }

  // 发送文本数据
  Future<void> _sendTextData() async {
    if (!_isConnected || _port == null) {
      _showError('请先连接串口');
      return;
    }

    final text = _sendDataController.text;
    if (text.isEmpty) {
      _showError('请输入要发送的数据');
      return;
    }

    try {
      // 转换为字节数组
      final data = Uint8List.fromList(text.codeUnits);

      // 发送数据
      final bytesWritten = await _port!.write(data);

      _addToReceivedData('发送($bytesWritten字节): $text', isTx: true);

      // 清空发送框
      _sendDataController.clear();
    } catch (e) {
      _showError('发送失败: $e');
    }
  }

  // 发送HEX数据
  Future<void> _sendHexData() async {
    if (!_isConnected || _port == null) {
      _showError('请先连接串口');
      return;
    }

    final hexText = _hexDataController.text.replaceAll(' ', '');
    if (hexText.isEmpty) {
      _showError('请输入要发送的HEX数据');
      return;
    }

    try {
      // 检查是否是有效的HEX字符串
      if (hexText.length % 2 != 0 ||
          !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(hexText)) {
        throw '无效的HEX格式';
      }

      // 转换为字节数组
      final List<int> bytes = [];
      for (int i = 0; i < hexText.length; i += 2) {
        final hex = hexText.substring(i, i + 2);
        bytes.add(int.parse(hex, radix: 16));
      }

      // 发送数据
      final data = Uint8List.fromList(bytes);
      final bytesWritten = await _port!.write(data);

      // 格式化显示
      final hexFormatted = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      _addToReceivedData('发送HEX($bytesWritten字节): $hexFormatted', isTx: true);

      // 清空发送框
      _hexDataController.clear();
    } catch (e) {
      _showError('发送失败: $e');
    }
  }

  // 处理接收到的数据
  void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;

    if (_showAsHex) {
      // 以HEX格式显示
      final hexStr = data
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      _addToReceivedData('接收HEX(${data.length}字节): $hexStr', isRx: true);
    } else {
      // 尝试以文本格式显示
      try {
        final text = String.fromCharCodes(data);
        _addToReceivedData('接收(${data.length}字节): $text', isRx: true);
      } catch (e) {
        // 如果无法转换为文本，则以HEX格式显示
        final hexStr = data
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        _addToReceivedData('接收HEX(${data.length}字节): $hexStr', isRx: true);
      }
    }
  }

  // 添加数据到接收缓冲区并更新UI
  void _addToReceivedData(
    String message, {
    bool isRx = false,
    bool isTx = false,
    bool isStatus = false,
  }) {
    if (!mounted) return;

    setState(() {
      // 添加前缀
      final String prefix =
          isRx
              ? '📥 '
              : isTx
              ? '📤 '
              : isStatus
              ? '🔔 '
              : '';

      // 添加时间戳和消息
      final timestamp = DateTime.now().toString().substring(11, 23);
      _receivedData.add('[$timestamp] $prefix$message');

      // 限制缓冲区大小
      if (_receivedData.length > _maxBufferLines) {
        _receivedData.removeAt(0);
      }
    });
  }

  // 清空接收缓冲区
  void _clearReceivedData() {
    if (!mounted) return;

    setState(() {
      _receivedData.clear();
      _addToReceivedData('清空了接收缓冲区', isStatus: true);
    });
  }

  // 显示错误消息
  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
    _addToReceivedData('错误: $message', isStatus: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 增加操作按钮行，替代原AppBar中的操作按钮
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings_applications),
                  onPressed: _isConnecting ? null : _showSerialConfigDialog,
                  tooltip: '串口配置',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshPorts,
                  tooltip: '刷新串口列表',
                ),
                IconButton(
                  icon: Icon(
                    _showAsHex ? Icons.text_fields : Icons.hexagon_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _showAsHex = !_showAsHex;
                    });
                  },
                  tooltip: _showAsHex ? '切换到文本模式' : '切换到HEX模式',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _clearReceivedData,
                  tooltip: '清空接收区',
                ),
              ],
            ),
          ),

          // 串口控制面板
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Text('串口: '),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedPort,
                        hint: const Text('选择串口'),
                        onChanged:
                            _isConnected
                                ? null
                                : (String? newValue) {
                                  setState(() {
                                    _selectedPort = newValue;
                                  });
                                },
                        items:
                            _availablePorts.map<DropdownMenuItem<String>>((
                              String value,
                            ) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_isConnecting)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      ElevatedButton(
                        onPressed: _toggleConnection,
                        child: Text(_isConnected ? '断开' : '连接'),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 接收数据显示区域
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(8.0),
              child: ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: _receivedData.length,
                itemBuilder: (context, index) {
                  final data = _receivedData[index];
                  Color textColor = Colors.black;

                  if (data.contains('📥')) {
                    textColor = Colors.blue;
                  } else if (data.contains('📤')) {
                    textColor = Colors.green;
                  } else if (data.contains('错误:')) {
                    textColor = Colors.red;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      data,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: textColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 发送区域
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 文本发送区
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sendDataController,
                          decoration: const InputDecoration(
                            labelText: '文本发送',
                            hintText: '输入要发送的文本',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendTextData(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isConnected ? _sendTextData : null,
                        child: const Text('发送'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // HEX发送区
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hexDataController,
                          decoration: const InputDecoration(
                            labelText: 'HEX发送',
                            hintText: '输入要发送的HEX数据 (例如: FF 00 A1)',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendHexData(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isConnected ? _sendHexData : null,
                        child: const Text('发送HEX'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
