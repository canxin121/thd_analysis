// 单片机命令相关常量
class SerialCommand {
  // 数据包大小与标识
  static const int uartPacketSize = 8;
  static const int packetHeader = 0xAA;
  static const int packetFooter = 0x55;

  // 命令码
  static const int cmdSetAutoMode = 0x01;
  static const int cmdSetTriggerMode = 0x02;
  static const int cmdGetModeStatus = 0x03;
  static const int cmdTriggerOnce = 0x04;

  // 响应状态码
  static const int respOk = 0x00;
  static const int respError = 0x01;
  static const int respBusy = 0x02;

  // 模式值
  static const int modeAuto = 0x01;
  static const int modeTrigger = 0x02;

  // 分析结果数据包标记
  static const List<int> dataPacketHeader = [0xBB, 0xBB];
  static const List<int> dataPacketFooter = [0xEE, 0xEE];
}
