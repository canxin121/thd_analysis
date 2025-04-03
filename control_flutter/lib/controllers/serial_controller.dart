import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/serial.dart';
import '../types/adc_data_analysis.dart';

class SerialController extends ChangeNotifier {
  // 串口相关状态
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isConnected = false;
  bool _isConnecting = false;

  // 数据采集相关状态
  AdcDataAndAnalysisResult? _analysisResult;
  bool _isLoading = false;
  String _errorMessage = '';

  // 自动触发相关状态
  bool _autoTrigger = false;
  Timer? _triggerTimer;
  int _triggerInterval = 1000; // 默认1秒

  // Getters
  List<String> get availablePorts => _availablePorts;
  String? get selectedPort => _selectedPort;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  AdcDataAndAnalysisResult? get analysisResult => _analysisResult;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get autoTrigger => _autoTrigger;
  int get triggerInterval => _triggerInterval;

  SerialController() {
    refreshPorts();
  }

  @override
  void dispose() {
    // 先停止自动触发
    stopAutoTrigger();
    // 添加短暂延迟，确保定时器完全停止
    Future.delayed(const Duration(milliseconds: 50), () {
      SerialApi.stopSerial();
    });
    super.dispose();
  }

  // 刷新可用串口列表
  void refreshPorts() {
    final newPorts = SerialApi.getAvailablePorts();

    _availablePorts = newPorts;

    // 检查当前选择的端口是否在新的端口列表中
    if (_selectedPort != null && !_availablePorts.contains(_selectedPort)) {
      // 如果当前选择的端口不在列表中，则重置选择
      _selectedPort = _availablePorts.isNotEmpty ? _availablePorts.first : null;
    } else if (_selectedPort == null && _availablePorts.isNotEmpty) {
      // 如果当前没有选择端口，但有可用端口，则选择第一个
      _selectedPort = _availablePorts.first;
    }

    notifyListeners();
  }

  // 设置选择的端口
  void setSelectedPort(String? port) {
    if (!_isConnected && port != null) {
      _selectedPort = port;
      notifyListeners();
    }
  }

  // 清除错误信息
  void clearErrorMessage() {
    _errorMessage = '';
    notifyListeners();
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
      _errorMessage = '请选择串口';
      notifyListeners();
      return;
    }

    _isConnecting = true;
    _errorMessage = '';
    notifyListeners();

    try {
      await SerialApi.startSerial(
        SerialConfig(portName: _selectedPort!, baudRate: 115200),
      );

      _isConnected = true;
      _isConnecting = false;
      notifyListeners();

      // 连接成功后立即触发一次采样
      triggerSample();
    } catch (e) {
      _isConnecting = false;
      _errorMessage = '连接失败: $e';
      notifyListeners();
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
      _isConnected = false;
      _analysisResult = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '断开失败: $e';
      notifyListeners();
    }
  }

  // 触发一次采样
  Future<void> triggerSample() async {
    if (!_isConnected) return;
    final bool manualTriggered = !_autoTrigger; // 手动采样标记

    if (manualTriggered) {
      _isLoading = true;
      _errorMessage = '';
      notifyListeners();
    }

    try {
      // 确认串口仍然连接着，避免在关闭过程中还触发采样
      if (!_isConnected) return;

      final result = await SerialApi.triggerSample();

      // 再次确认状态，防止在等待过程中串口已被关闭
      if (!_isConnected) return;

      _analysisResult = result;
      if (manualTriggered) {
        _isLoading = false;
      }
      notifyListeners();
    } catch (e) {
      if (manualTriggered) {
        _isLoading = false;
      }
      _errorMessage = '获取数据失败: $e';
      notifyListeners();
    }
  }

  // 开始自动触发
  void startAutoTrigger() {
    if (!_isConnected) return;

    _triggerTimer = Timer.periodic(
      Duration(milliseconds: _triggerInterval),
      (_) => triggerSample(),
    );

    _autoTrigger = true;
    notifyListeners();
  }

  // 停止自动触发
  void stopAutoTrigger() {
    _triggerTimer?.cancel();
    _triggerTimer = null;

    _autoTrigger = false;
    notifyListeners();
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
    if (interval >= 500 && interval <= 10000) {
      _triggerInterval = interval;

      // 如果已经在自动触发，重新开始计时
      if (_autoTrigger) {
        stopAutoTrigger();
        startAutoTrigger();
      }

      notifyListeners();
    }
  }
}
