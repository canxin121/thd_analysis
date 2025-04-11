import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../types/command.dart';
import '../types/adc_data_analysis.dart';

/// 串口配置类
class SerialConfig {
  String portName;
  int baudRate;
  int dataBits;
  int parity; // 修改为int类型，不再使用SerialPortParity枚举
  int stopBits;
  int flowControl; // 修改为int类型，不再使用SerialPortFlowControl枚举
  int timeoutMs;

  SerialConfig({
    required this.portName,
    this.baudRate = 921600,
    this.dataBits = 8,
    this.parity = SerialPortParity.none,
    this.stopBits = 1,
    this.flowControl = SerialPortFlowControl.none,
    this.timeoutMs = 100,
  });

  SerialConfig.defaultConfig()
    : portName = "PortName",
      baudRate = 921600,
      dataBits = 8,
      parity = SerialPortParity.none,
      stopBits = 1,
      flowControl = SerialPortFlowControl.none,
      timeoutMs = 100;
}

/// 命令响应类
class CommandResponse {
  final int command;
  final int status;
  final int data;

  CommandResponse({
    required this.command,
    required this.status,
    required this.data,
  });
}

/// 串口通信管理类
class SerialApi {
  static SerialPort? _port;
  static SerialPortReader? _reader;
  static StreamSubscription? _subscription;

  // 数据接收相关
  static final StreamController<Uint8List> _dataStreamController =
      StreamController<Uint8List>.broadcast();
  static Stream<Uint8List> get dataStream => _dataStreamController.stream;

  // 临时数据缓冲区
  static final List<int> _buffer = [];

  // 标记是否正在等待命令响应
  static bool _waitingForResponse = false;
  static Completer<CommandResponse>? _responseCompleter;

  // 标记是否正在等待数据包
  static bool _waitingForDataPacket = false;
  static Completer<List<int>>? _dataPacketCompleter;

  /// 获取可用串口列表
  static Future<List<String>> getAvailablePorts() async {
    try {
      final portsResult = await SerialPort.availablePorts;
      final uniquePorts = portsResult.toSet().toList();
      final ports = uniquePorts.toList();
      ports.sort();
      return ports;
    } catch (e) {
      throw '获取串口列表失败: $e';
    }
  }

  /// 开启串口连接
  static Future<void> startSerial(SerialConfig config) async {
    // 如果已连接，先断开
    if (_port != null) {
      await stopSerial();
    }

    try {
      // 创建串口对象
      _port = SerialPort(config.portName);

      // 打开串口
      if (!await _port!.openReadWrite()) {
        throw '无法打开串口进行读写操作';
      }

      // 配置串口
      final portConfig = SerialPortConfig();
      portConfig.baudRate = config.baudRate;
      portConfig.bits = config.dataBits;
      portConfig.parity = config.parity; // 直接使用整数值
      portConfig.stopBits = config.stopBits;
      portConfig.setFlowControl(config.flowControl); // 直接使用整数值

      // 应用配置
      await _port!.setConfig(portConfig);

      // 创建读取器并订阅数据
      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen(
        _onDataReceived,
        onError: (error) {
          if (kDebugMode) {
            print('数据接收错误: $error');
          }
          // 如果有正在等待响应的Completer，以错误结束它
          if (_waitingForResponse &&
              _responseCompleter != null &&
              !_responseCompleter!.isCompleted) {
            _responseCompleter!.completeError('数据接收错误: $error');
          }
          if (_waitingForDataPacket &&
              _dataPacketCompleter != null &&
              !_dataPacketCompleter!.isCompleted) {
            _dataPacketCompleter!.completeError('数据接收错误: $error');
          }
        },
      );

      // 设置为触发模式
      await setTriggerMode();
    } catch (e) {
      if (_port != null) {
        if (_port!.isOpen) {
          await _port!.close();
        }
        _port!.dispose();
        _port = null;
      }
      throw '无法打开串口: $e';
    }
  }

  /// 停止串口连接
  static Future<void> stopSerial() async {
    // 取消任何未完成的等待
    if (_waitingForResponse &&
        _responseCompleter != null &&
        !_responseCompleter!.isCompleted) {
      _responseCompleter!.completeError('串口已关闭');
    }
    if (_waitingForDataPacket &&
        _dataPacketCompleter != null &&
        !_dataPacketCompleter!.isCompleted) {
      _dataPacketCompleter!.completeError('串口已关闭');
    }

    _waitingForResponse = false;
    _waitingForDataPacket = false;
    _buffer.clear();

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
  }

  /// 处理接收到的数据
  static void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;

    // 添加到广播流
    _dataStreamController.add(data);

    // 添加到缓冲区
    _buffer.addAll(data);

    // 如果正在等待命令响应，尝试解析
    if (_waitingForResponse &&
        _responseCompleter != null &&
        !_responseCompleter!.isCompleted) {
      _tryParseCommandResponse();
    }

    // 如果正在等待数据包，尝试解析
    if (_waitingForDataPacket &&
        _dataPacketCompleter != null &&
        !_dataPacketCompleter!.isCompleted) {
      _tryParseDataPacket();
    }
  }

  /// 尝试从缓冲区解析命令响应
  static void _tryParseCommandResponse() {
    // 命令响应包固定为8字节
    if (_buffer.length >= SerialCommand.uartPacketSize) {
      // 查找包头
      int startIndex = -1;
      for (int i = 0; i <= _buffer.length - SerialCommand.uartPacketSize; i++) {
        if (_buffer[i] == SerialCommand.packetHeader &&
            _buffer[i + SerialCommand.uartPacketSize - 1] ==
                SerialCommand.packetFooter) {
          startIndex = i;
          break;
        }
      }

      if (startIndex >= 0) {
        // 提取响应包
        final packet = _buffer.sublist(
          startIndex,
          startIndex + SerialCommand.uartPacketSize,
        );

        // 清除已使用的数据
        _buffer.removeRange(0, startIndex + SerialCommand.uartPacketSize);

        // 解析响应
        final response = CommandResponse(
          command: packet[1],
          status: packet[2],
          data: packet[3],
        );

        // 完成等待
        _waitingForResponse = false;
        _responseCompleter!.complete(response);
      }
    }
  }

  /// 尝试从缓冲区解析数据包
  static void _tryParseDataPacket() {
    // 首先查找包头序列
    int headerIndex = _findSequence(_buffer, analysisPacketStart);
    if (headerIndex >= 0) {
      // 找到包头，现在查找包尾
      int footerIndex = _findSequence(
        _buffer,
        analysisPacketEnd,
        headerIndex + analysisPacketStart.length,
      );

      if (footerIndex >= 0) {
        // 找到完整数据包
        final dataPacket = _buffer.sublist(
          headerIndex,
          footerIndex + analysisPacketEnd.length,
        );

        // 清除已使用的数据
        _buffer.removeRange(0, footerIndex + analysisPacketEnd.length);

        // 完成等待
        _waitingForDataPacket = false;
        _dataPacketCompleter!.complete(dataPacket);
      }
    }
  }

  /// 在数组中查找序列
  static int _findSequence(
    List<int> array,
    List<int> sequence, [
    int startFrom = 0,
  ]) {
    for (int i = startFrom; i <= array.length - sequence.length; i++) {
      bool found = true;
      for (int j = 0; j < sequence.length; j++) {
        if (array[i + j] != sequence[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  /// 更新串口配置
  static Future<void> updateSerialConfig(SerialConfig config) async {
    await startSerial(config);
  }

  /// 触发一次采样并返回结果
  static Future<AdcDataAndAnalysisResult> triggerSample() async {
    if (_port == null || !_port!.isOpen) {
      throw "串口未连接";
    }

    List<int> packet = await triggerOnceAndWaitResult();
    return processAnalysisPacket(packet);
  }

  /// 创建命令包
  static Uint8List _createCommandPacket(int cmd, List<int> data) {
    final packet = Uint8List(SerialCommand.uartPacketSize);
    packet[0] = SerialCommand.packetHeader;
    packet[1] = cmd;

    // 复制数据部分（最多5字节）
    final dataLen = data.length > 5 ? 5 : data.length;
    if (dataLen > 0) {
      packet.setRange(2, 2 + dataLen, data);
    }

    packet[SerialCommand.uartPacketSize - 1] = SerialCommand.packetFooter;
    return packet;
  }

  /// 发送命令并等待响应
  static Future<CommandResponse> sendCommandAndWaitResponse(
    int cmd,
    List<int> data,
  ) async {
    if (_port == null || !_port!.isOpen) {
      throw "串口未连接";
    }

    // 确保没有正在进行的命令
    if (_waitingForResponse) {
      throw "已有正在等待响应的命令";
    }

    // 准备等待响应
    _responseCompleter = Completer<CommandResponse>();
    _waitingForResponse = true;

    // 清空输入缓冲区
    _port!.flush(SerialPortBuffer.input);
    _buffer.clear();

    // 创建命令包
    final cmdPacket = _createCommandPacket(cmd, data);

    try {
      // 发送命令
      final bytesWritten = await _port!.write(cmdPacket);
      if (bytesWritten != cmdPacket.length) {
        throw "发送命令失败：发送了 $bytesWritten 字节，应为 ${cmdPacket.length} 字节";
      }

      // 设置超时
      final timeout = const Duration(seconds: 5);
      return await _responseCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          _waitingForResponse = false;
          throw "等待响应超时";
        },
      );
    } catch (e) {
      _waitingForResponse = false;
      throw "发送命令失败: $e";
    }
  }

  /// 触发一次采样并等待结果
  static Future<List<int>> triggerOnceAndWaitResult() async {
    // 发送触发命令
    final response = await sendCommandAndWaitResponse(
      SerialCommand.cmdTriggerOnce,
      [],
    );

    if (response.status == SerialCommand.respBusy) {
      throw "设备忙，无法触发采样";
    } else if (response.status == SerialCommand.respError) {
      throw "设备拒绝触发请求（可能不在触发模式）";
    } else if (response.status != SerialCommand.respOk) {
      throw "触发请求返回未知状态: ${response.status}";
    }

    // 准备等待数据包
    _dataPacketCompleter = Completer<List<int>>();
    _waitingForDataPacket = true;

    try {
      // 设置超时
      final timeout = const Duration(seconds: 10);
      return await _dataPacketCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          _waitingForDataPacket = false;
          throw "等待数据包超时";
        },
      );
    } catch (e) {
      _waitingForDataPacket = false;
      throw "读取数据失败: $e";
    }
  }

  /// 设置为触发模式
  static Future<void> setTriggerMode() async {
    final response = await sendCommandAndWaitResponse(
      SerialCommand.cmdSetTriggerMode,
      [],
    );

    if (!(response.status == SerialCommand.respOk &&
        response.data == SerialCommand.modeTrigger)) {
      throw "设置触发模式失败: 状态=${response.status}, 数据=${response.data}";
    }
  }
}
