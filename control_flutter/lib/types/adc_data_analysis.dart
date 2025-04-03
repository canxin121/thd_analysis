import 'dart:typed_data';

/// 波形类型枚举，对应Rust中的WaveformType
enum WaveformType {
  none, // 无有效波形或未找到基波
  dc, // 直流信号
  sine, // 正弦波
  square, // 方波
  triangle, // 三角波
  sawtooth, // 锯齿波
  unknown, // 未知或无法归类的波形
}

/// ADC数据类，对应Rust中的AdcData结构体
class AdcData {
  List<int> data; // 使用int类型存储u16数据

  AdcData(this.data);

  /// 默认构造函数
  AdcData.empty() : data = [];

  /// 从字节数组构造ADC数据
  factory AdcData.fromBytes(List<int> bytes) {
    if (bytes.length % 2 != 0) {
      throw Exception("字节数组长度不正确: 应为偶数");
    }

    List<int> samples = [];
    for (int i = 0; i < bytes.length; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8); // little-endian
      samples.add(sample);
    }

    return AdcData(samples);
  }

  /// 转换为字节数组
  List<int> toBytes() {
    List<int> bytes = [];
    for (int sample in data) {
      bytes.add(sample & 0xFF); // 低字节
      bytes.add((sample >> 8) & 0xFF); // 高字节
    }
    return bytes;
  }
}

/// 谐波分析结果类，对应Rust中的AnalysisResult
class AnalysisResult {
  double thd; // 总谐波失真 (%)
  List<double> normalizedHarmonics; // 归一化谐波幅度
  List<int> harmonicIndices; // 谐波索引
  int fundamentalFreq; // 基波频率
  WaveformType waveform; // 波形类型
  bool hasDcOffset; // 是否有直流偏移

  AnalysisResult({
    required this.thd,
    required this.normalizedHarmonics,
    required this.harmonicIndices,
    required this.fundamentalFreq,
    required this.waveform,
    required this.hasDcOffset,
  });

  /// 默认构造函数
  AnalysisResult.empty()
    : thd = 0.0,
      normalizedHarmonics = [],
      harmonicIndices = [],
      fundamentalFreq = 0,
      waveform = WaveformType.unknown,
      hasDcOffset = false;

  /// 从字节数组构造分析结果
  factory AnalysisResult.fromBytes(List<int> data, int numHarmonics) {
    int expectedLen = 4 + 4 * numHarmonics + 4 * numHarmonics + 4 + 1 + 1;
    if (data.length < expectedLen) {
      throw Exception("数据长度不足: 实际数据长度 ${data.length} vs 预期数据长度 $expectedLen");
    }

    int offset = 0;

    // 解析 thd (4字节)
    double thd = _bytesToFloat32(data.sublist(offset, offset + 4));
    offset += 4;

    // 解析 normalized_harmonics (4 * num_harmonics 字节)
    List<double> normalizedHarmonics = [];
    for (int i = 0; i < numHarmonics; i++) {
      double value = _bytesToFloat32(data.sublist(offset, offset + 4));
      normalizedHarmonics.add(value);
      offset += 4;
    }

    // 解析 harmonic_indices (4 * num_harmonics 字节)
    List<int> harmonicIndices = [];
    for (int i = 0; i < numHarmonics; i++) {
      int value = _bytesToUint32(data.sublist(offset, offset + 4));
      harmonicIndices.add(value);
      offset += 4;
    }

    // 解析 fundamental_freq (4字节)
    int fundamentalFreq = _bytesToUint32(data.sublist(offset, offset + 4));
    offset += 4;

    // 解析 waveform (1字节)
    WaveformType waveform = _intToWaveformType(data[offset]);
    offset += 1;

    // 解析 has_dc_offset (1字节)
    bool hasDcOffset = data[offset] != 0;

    return AnalysisResult(
      thd: thd,
      normalizedHarmonics: normalizedHarmonics,
      harmonicIndices: harmonicIndices,
      fundamentalFreq: fundamentalFreq,
      waveform: waveform,
      hasDcOffset: hasDcOffset,
    );
  }

  /// 辅助函数：将整数转换为WaveformType
  static WaveformType _intToWaveformType(int value) {
    switch (value) {
      case 0:
        return WaveformType.none;
      case 1:
        return WaveformType.dc;
      case 2:
        return WaveformType.sine;
      case 3:
        return WaveformType.square;
      case 4:
        return WaveformType.triangle;
      case 5:
        return WaveformType.sawtooth;
      default:
        return WaveformType.unknown;
    }
  }

  /// 辅助函数：字节数组转float32
  static double _bytesToFloat32(List<int> bytes) {
    final byteData = ByteData(4);
    for (int i = 0; i < 4; i++) {
      byteData.setUint8(i, bytes[i]); // 保持little-endian顺序
    }
    return byteData.getFloat32(0, Endian.little);
  }

  /// 辅助函数：字节数组转uint32
  static int _bytesToUint32(List<int> bytes) {
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }
}

/// 组合类型，对应Rust中的AdcDataAndAnalysisResult
class AdcDataAndAnalysisResult {
  AdcData adcData;
  AnalysisResult harmonicsAnalysis;

  AdcDataAndAnalysisResult({
    required this.adcData,
    required this.harmonicsAnalysis,
  });

  /// 默认构造函数
  AdcDataAndAnalysisResult.empty()
    : adcData = AdcData.empty(),
      harmonicsAnalysis = AnalysisResult.empty();
}

/// 数据包标识常量
const List<int> analysisPacketStart = [0xAA, 0x55, 0xA5, 0x5A, 0xAA];
const List<int> analysisPacketEnd = [0xBB, 0x66, 0xB6, 0x6B, 0xBB];

/// 处理分析数据包，对应Rust中的process_analysis_packet函数
AdcDataAndAnalysisResult processAnalysisPacket(List<int> packet) {
  // 确认包头和包尾
  if (!_listStartsWith(packet, analysisPacketStart) ||
      !_listEndsWith(packet, analysisPacketEnd)) {
    throw Exception("数据包格式错误: 包头或包尾不匹配");
  }

  // 提取SAMPLE_SIZE和NUM_HARMONICS
  if (packet.length < analysisPacketStart.length + 3) {
    throw Exception("数据包太短，无法提取参数");
  }

  int sampleSizeLow = packet[analysisPacketStart.length];
  int sampleSizeHigh = packet[analysisPacketStart.length + 1];
  int sampleSize = (sampleSizeHigh << 8) | sampleSizeLow;
  int numHarmonics = packet[analysisPacketStart.length + 2];

  // 提取数据部分（不包括包头、大小参数和包尾）
  List<int> data = packet.sublist(
    analysisPacketStart.length + 3,
    packet.length - analysisPacketEnd.length,
  );

  // 预期数据长度计算
  int expectedAdcLen = 2 * sampleSize;
  int expectedResultLen =
      4 // thd
      +
      4 // fundamental_freq
      +
      4 *
          numHarmonics // normalized_harmonics
          +
      4 *
          numHarmonics // harmonic_indices
          +
      1 // waveform
      +
      1; // has_dc_offset

  int expectedTotalDataLen = expectedAdcLen + expectedResultLen;

  if (data.length != expectedTotalDataLen) {
    throw Exception(
      "数据长度不符: 实际数据长度 ${data.length} vs 预期数据长度 $expectedTotalDataLen",
    );
  }

  // 解析ADC数据
  AdcData adcData = AdcData.fromBytes(data.sublist(0, expectedAdcLen));

  // 解析谐波分析结果
  AnalysisResult harmonicsAnalysis = AnalysisResult.fromBytes(
    data.sublist(expectedAdcLen),
    numHarmonics,
  );

  // 返回组合结果
  return AdcDataAndAnalysisResult(
    adcData: adcData,
    harmonicsAnalysis: harmonicsAnalysis,
  );
}

/// 辅助函数：检查列表是否以另一个列表开头
bool _listStartsWith(List<int> list, List<int> prefix) {
  if (list.length < prefix.length) return false;
  for (int i = 0; i < prefix.length; i++) {
    if (list[i] != prefix[i]) return false;
  }
  return true;
}

/// 辅助函数：检查列表是否以另一个列表结尾
bool _listEndsWith(List<int> list, List<int> suffix) {
  if (list.length < suffix.length) return false;
  for (int i = 0; i < suffix.length; i++) {
    if (list[list.length - suffix.length + i] != suffix[i]) return false;
  }
  return true;
}
