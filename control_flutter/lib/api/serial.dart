import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../types/command.dart';
import '../types/adc_data_analysis.dart';

/// 串口配置类
class SerialConfig {
  String portName;
  int baudRate;
  int timeoutMs;

  SerialConfig({
    required this.portName,
    this.baudRate = 115200,
    this.timeoutMs = 100,
  });

  SerialConfig.defaultConfig()
    : portName = "PortName",
      baudRate = 115200,
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

  /// 获取可用串口列表
  static List<String> getAvailablePorts() {
    List<String> ports = SerialPort.availablePorts;
    ports = ports.toSet().toList();
    ports.sort();
    return ports;
  }

  /// 开启串口连接
  static Future<void> startSerial(SerialConfig config) async {
    // 如果已连接，先断开
    if (_port != null) {
      await stopSerial();
    }

    try {
      _port = SerialPort(config.portName);

      // openReadWrite() 打开串口用于读写操作
      if (!_port!.openReadWrite()) {
        throw "无法打开串口进行读写操作";
      }

      // 配置串口参数
      var portConfig = _port!.config;
      portConfig.baudRate = config.baudRate;
      portConfig.bits = 8;
      portConfig.parity = SerialPortParity.none;
      portConfig.stopBits = 1;
      portConfig.setFlowControl(SerialPortFlowControl.none);

      // 应用配置
      _port!.config = portConfig;

      // 设置为触发模式
      await setTriggerMode();

      // 初始化读取器
      _reader = SerialPortReader(_port!);
    } catch (e) {
      if (_port != null) {
        _port!.close();
        _port!.dispose();
        _port = null;
      }
      throw "无法打开串口: $e";
    }
  }

  /// 停止串口连接
  static Future<void> stopSerial() async {
    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }

    if (_reader != null) {
      _reader = null;
    }

    if (_port != null) {
      if (_port!.isOpen) {
        _port!.close();
      }
      _port!.dispose();
      _port = null;
    }
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

    // 清空输入缓冲区
    _port!.flush(SerialPortBuffer.input);

    final cmdPacket = _createCommandPacket(cmd, data);

    // 发送命令 - 修改为正确的write方法调用
    _port!.write(cmdPacket);

    // 读取响应（8字节）
    Uint8List response = Uint8List(0);
    final startTime = DateTime.now();
    final timeout = const Duration(seconds: 5);

    // 循环读取数据直到获得完整的响应包
    while (response.length < SerialCommand.uartPacketSize) {
      if (DateTime.now().difference(startTime) > timeout) {
        throw "等待响应超时";
      }

      try {
        // 使用非阻塞方式读取剩余的字节
        if (_port!.bytesAvailable > 0) {
          final newBytes = _port!.read(
            SerialCommand.uartPacketSize - response.length,
          );

          // 合并读取到的数据
          if (newBytes.isNotEmpty) {
            final temp = Uint8List(response.length + newBytes.length);
            temp.setRange(0, response.length, response);
            temp.setRange(response.length, temp.length, newBytes);
            response = temp;
          }
        } else {
          // 短暂延迟，避免CPU占用过高
          await Future.delayed(const Duration(milliseconds: 5));
        }
      } catch (e) {
        // 如果是超时错误，继续尝试
        if (e.toString().contains("timeout")) {
          continue;
        }
        throw "读取错误: $e";
      }
    }

    // 验证响应
    if (response[0] != SerialCommand.packetHeader ||
        response[SerialCommand.uartPacketSize - 1] !=
            SerialCommand.packetFooter) {
      throw "无效的响应包格式";
    }

    if (response[1] != cmd) {
      throw "命令回显不匹配: 期望 0x${cmd.toRadixString(16).padLeft(2, '0')}, "
          "收到 0x${response[1].toRadixString(16).padLeft(2, '0')}";
    }

    return CommandResponse(
      command: response[1],
      status: response[2],
      data: response[3],
    );
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

    // 寻找数据包头部
    List<int> buffer = [];
    bool headerFound = false;
    int headerPos = 0;
    final startTime = DateTime.now();
    final timeout = const Duration(seconds: 5);

    // libserialport 没有直接的超时配置方法，我们只能通过读取方式控制
    try {
      // 读取直到找到包头
      while (!headerFound) {
        if (DateTime.now().difference(startTime) > timeout) {
          throw "等待数据包头部超时";
        }

        if (_port!.bytesAvailable > 0) {
          // 一次读取一个字节
          final byte = _port!.read(1);

          if (byte.isNotEmpty) {
            buffer.add(byte[0]);

            // 检查是否匹配包头序列
            if (byte[0] == analysisPacketStart[headerPos]) {
              headerPos++;
              if (headerPos == analysisPacketStart.length) {
                headerFound = true;
              }
            } else {
              // 不匹配，重置位置
              headerPos = 0;
              // 如果当前字节匹配包头第一个字节，重新开始匹配
              if (byte[0] == analysisPacketStart[0]) {
                headerPos = 1;
              }
            }
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 5));
        }

        // 保持缓冲区大小合理
        if (buffer.length > 1000 && !headerFound) {
          buffer = buffer.sublist(buffer.length - 100);
        }
      }

      // 修剪buffer，只保留包头及之后的数据
      final headerStartIdx = buffer.length - analysisPacketStart.length;
      buffer = buffer.sublist(headerStartIdx);

      // 读取SAMPLE_SIZE和NUM_HARMONICS (3字节)
      int bytesNeeded = 3;
      final sizeStartTime = DateTime.now();

      while (bytesNeeded > 0) {
        if (DateTime.now().difference(sizeStartTime) > timeout) {
          throw "读取大小参数超时";
        }

        if (_port!.bytesAvailable > 0) {
          final newBytes = _port!.read(bytesNeeded);
          if (newBytes.isNotEmpty) {
            buffer.addAll(newBytes);
            bytesNeeded -= newBytes.length;
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }

      // 继续读取数据直到找到包尾
      final longStartTime = DateTime.now();
      bool footerFound = false;
      int footerPos = 0;
      final longTimeout = const Duration(seconds: 10);

      while (!footerFound) {
        if (DateTime.now().difference(longStartTime) > longTimeout) {
          throw "读取数据超时";
        }

        if (_port!.bytesAvailable > 0) {
          final temp = _port!.read(128); // 每次最多读取128字节

          if (temp.isNotEmpty) {
            // 添加到缓冲区
            buffer.addAll(temp);

            // 检查是否包含包尾序列的一部分
            for (int i = 0; i < temp.length; i++) {
              final currentByte = temp[i];
              if (currentByte == analysisPacketEnd[footerPos]) {
                footerPos++;
                if (footerPos == analysisPacketEnd.length) {
                  footerFound = true;
                  break;
                }
              } else {
                // 如果当前字节匹配包尾的第一个字节，重置为1
                footerPos = (currentByte == analysisPacketEnd[0]) ? 1 : 0;
              }
            }
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 5));
        }

        // 防止无限循环占用内存
        if (buffer.length > 1000000) {
          throw "数据包过大，可能损坏";
        }
      }

      return buffer;
    } catch (e) {
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
