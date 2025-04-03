import 'types/adc_data_analysis.dart';

// 获取波形类型名称
String getWaveformTypeName(WaveformType type) {
  switch (type) {
    case WaveformType.none:
      return '无有效波形';
    case WaveformType.dc:
      return '直流信号';
    case WaveformType.sine:
      return '正弦波';
    case WaveformType.square:
      return '方波';
    case WaveformType.triangle:
      return '三角波';
    case WaveformType.sawtooth:
      return '锯齿波';
    case WaveformType.unknown:
      return '未知波形';
  }
}

// 判断当前是否为横屏模式
bool isLandscapeMode(double screenWidth) {
  // 通常以768px作为平板/桌面设备的分界点
  return screenWidth >= 768;
}
