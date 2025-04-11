import 'dart:async';
import 'package:flutter/material.dart';
import '../api/serial.dart';
import '../waveform_utils.dart';
import '../widgets/waveform_chart.dart';
import '../widgets/analysis_result_display.dart';
import '../widgets/serial_control_panel.dart';
import '../widgets/serial_config_dialog.dart';
import '../types/adc_data_analysis.dart';

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // 串口相关状态
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isConnected = false;
  bool _isConnecting = false;
  SerialConfig _serialConfig = SerialConfig.defaultConfig();

  // 数据采集相关状态
  AdcDataAndAnalysisResult? _analysisResult;
  bool _isLoading = false;
  String _errorMessage = '';

  // 自动触发相关状态
  bool _autoTrigger = false;
  Timer? _triggerTimer;
  int _triggerInterval = 500; // 默认0.5秒

  @override
  void initState() {
    super.initState();
    refreshPorts();
  }

  @override
  void dispose() {
    // 先停止自动触发
    stopAutoTrigger();
    // 添加短暂延迟，确保定时器完全停止
    Future.delayed(const Duration(milliseconds: 50), () async {
      await SerialApi.stopSerial();
    });
    super.dispose();
  }

  // 刷新可用串口列表
  Future<void> refreshPorts() async {
    try {
      final newPorts = await SerialApi.getAvailablePorts();

      if (mounted) {
        setState(() {
          _availablePorts = newPorts;

          // 检查当前选择的端口是否在新的端口列表中
          if (_selectedPort != null &&
              !_availablePorts.contains(_selectedPort)) {
            // 如果当前选择的端口不在列表中，则重置选择
            _selectedPort =
                _availablePorts.isNotEmpty ? _availablePorts.first : null;
          } else if (_selectedPort == null && _availablePorts.isNotEmpty) {
            // 如果当前没有选择端口，但有可用端口，则选择第一个
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
        setState(() {
          _errorMessage = '刷新串口列表失败: $e';
        });
      }
    }
  }

  // 设置选择的端口
  void setSelectedPort(String? port) {
    if (!_isConnected && port != null) {
      setState(() {
        _selectedPort = port;
        _serialConfig.portName = port;
      });
    }
  }

  // 显示串口配置对话框
  void showSerialConfigDialog() {
    showDialog(
      context: context,
      builder:
          (context) => SerialConfigDialog(
            initialConfig: _serialConfig,
            onConfigChanged: (config) {
              setState(() {
                _serialConfig = config;

                // 如果当前已连接，需要更新连接
                if (_isConnected) {
                  _updateSerialConnection();
                }
              });
            },
          ),
    );
  }

  // 更新串口连接（应用新配置）
  Future<void> _updateSerialConnection() async {
    if (!_isConnected) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      await SerialApi.updateSerialConfig(_serialConfig);
      setState(() {
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _errorMessage = '更新串口配置失败: $e';
      });
    }
  }

  // 清除错误信息
  void clearErrorMessage() {
    setState(() {
      _errorMessage = '';
    });
  }

  // 连接/断开串口
  Future<void> toggleConnection() async {
    if (_isConnected) {
      await disconnectPort();
    } else {
      await connectPort();
    }
  }

  // 连接串口
  Future<void> connectPort() async {
    if (_selectedPort == null) {
      setState(() {
        _errorMessage = '请选择串口';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = '';
      _serialConfig.portName = _selectedPort!;
    });

    try {
      await SerialApi.startSerial(_serialConfig);

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
      }

      // 连接成功后立即触发一次采样
      await triggerSample();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = '连接失败: $e';
        });
      }
    }
  }

  // 断开串口
  Future<void> disconnectPort() async {
    // 先停止自动触发，确保所有定时器已被取消
    stopAutoTrigger();

    // 添加短暂延迟，确保定时器完全停止
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      await SerialApi.stopSerial();

      if (mounted) {
        setState(() {
          _isConnected = false;
          _analysisResult = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '断开失败: $e';
        });
      }
    }
  }

  // 触发一次采样
  Future<void> triggerSample() async {
    if (!_isConnected) return;
    final bool manualTriggered = !_autoTrigger; // 手动采样标记

    if (manualTriggered && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      // 确认串口仍然连接着，避免在关闭过程中还触发采样
      if (!_isConnected) return;

      final result = await SerialApi.triggerSample();

      // 再次确认状态，防止在等待过程中串口已被关闭
      if (!_isConnected || !mounted) return;

      setState(() {
        _analysisResult = result;
        if (manualTriggered) {
          _isLoading = false;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (manualTriggered) {
            _isLoading = false;
          }
          _errorMessage = '获取数据失败: $e';
        });
      }
    }
  }

  // 开始自动触发
  void startAutoTrigger() {
    if (!_isConnected) return;

    _triggerTimer = Timer.periodic(
      Duration(milliseconds: _triggerInterval),
      (_) async => await triggerSample(),
    );

    setState(() {
      _autoTrigger = true;
    });
  }

  // 停止自动触发
  void stopAutoTrigger() {
    _triggerTimer?.cancel();
    _triggerTimer = null;

    if (mounted) {
      setState(() {
        _autoTrigger = false;
      });
    }
  }

  // 切换自动触发状态
  void toggleAutoTrigger() {
    if (_autoTrigger) {
      stopAutoTrigger();
    } else {
      startAutoTrigger();
    }
  }

  // 设置触发间隔
  void setTriggerInterval(int interval) {
    if (interval >= 100 && interval <= 10000) {
      setState(() {
        _triggerInterval = interval;
      });

      // 如果已经在自动触发，重新开始计时
      if (_autoTrigger) {
        stopAutoTrigger();
        startAutoTrigger();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = isLandscapeMode(screenWidth);

    return Scaffold(
      body: Column(
        children: [
          // 串口控制面板
          SerialControlPanel(
            context: context,
            availablePorts: _availablePorts,
            selectedPort: _selectedPort,
            isConnected: _isConnected,
            isConnecting: _isConnecting,
            autoTrigger: _autoTrigger,
            triggerInterval: _triggerInterval,
            isLoading: _isLoading,
            isLandscape: isLandscape,
            onRefreshPorts: refreshPorts,
            onSetSelectedPort: setSelectedPort,
            onToggleConnection: toggleConnection,
            onToggleAutoTrigger: toggleAutoTrigger,
            onTriggerSample: triggerSample,
            onSetTriggerInterval: setTriggerInterval,
            onShowConfig: showSerialConfigDialog,
          ),

          // 错误消息显示
          if (_errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: clearErrorMessage,
                    color: Colors.red.shade700,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // 主内容区域 - 根据屏幕宽度选择布局方向
          Expanded(
            child:
                isLandscape
                    ? _buildLandscapeContentLayout()
                    : _buildPortraitContentLayout(context),
          ),
        ],
      ),
    );
  }

  // 横屏模式内容布局
  Widget _buildLandscapeContentLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 波形图
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '波形图',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: WaveformChart(analysisResult: _analysisResult)),
              ],
            ),
          ),
        ),

        // 分析结果
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '分析结果',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: AnalysisResultDisplay(
                    analysisResult: _analysisResult,
                    useInternalScroll: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 竖屏模式内容布局
  Widget _buildPortraitContentLayout(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 波形图 - 设置固定高度
          Container(
            height: MediaQuery.of(context).size.height * 0.4, // 屏幕高度的40%
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '波形图',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: WaveformChart(analysisResult: _analysisResult)),
              ],
            ),
          ),

          // 分析结果 - 不使用内部滚动，高度自适应内容
          Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '分析结果',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                AnalysisResultDisplay(
                  analysisResult: _analysisResult,
                  useInternalScroll: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
