#include "command.h"
#include "consts.h"
#include "uart_comm.h"
#include <stdint.h>

// 处理UART命令
void process_uart_command(uint8_t *packet, OperationMode *gCurrentMode,
                          SystemState *gSystemState, bool *gTriggerSampling) {
  // 检查包头和包尾
  if (packet[0] != UART_PACKET_HEAD || packet[7] != UART_PACKET_TAIL) {
    return; // 头尾验证失败，直接返回
  }

  // 解析命令
  uint8_t cmd = packet[1];

  switch (cmd) {
  case CMD_SET_AUTO_MODE:
    *gCurrentMode = MODE_AUTO;
    send_uart_response(CMD_SET_AUTO_MODE, RESP_OK, MODE_AUTO);
    break;

  case CMD_SET_TRIGGER_MODE:
    *gCurrentMode = MODE_TRIGGER;
    send_uart_response(CMD_SET_TRIGGER_MODE, RESP_OK, MODE_TRIGGER);
    break;

  case CMD_GET_MODE_STATUS:
    send_uart_response(CMD_GET_MODE_STATUS, RESP_OK, *gCurrentMode);
    break;

  case CMD_TRIGGER_ONCE:
    if (*gCurrentMode == MODE_TRIGGER) {
      if (*gSystemState == STATE_IDLE) {
        *gTriggerSampling = true;
        send_uart_response(CMD_TRIGGER_ONCE, RESP_OK, 0);
      } else {
        send_uart_response(CMD_TRIGGER_ONCE, RESP_BUSY, 0);
      }
    } else {
      send_uart_response(CMD_TRIGGER_ONCE, RESP_ERROR, 0);
    }
    break;

  case CMD_SET_AUTO_DELAY: {
    // 从命令包中获取延时值(ms)，使用2个字节表示(低字节在前)
    uint16_t delay_ms = (packet[2] | (packet[3] << 8));
    if (delay_ms >= 100 && delay_ms <= 10000) { // 限制范围在100ms~10s
      gAutoModeDelayMs = delay_ms;
      send_uart_response(CMD_SET_AUTO_DELAY, RESP_OK, delay_ms);
    } else {
      send_uart_response(CMD_SET_AUTO_DELAY, RESP_ERROR, 0);
    }
    break;
  }

  case CMD_GET_AUTO_DELAY:
    // 返回当前的延时值，返回完整值而不仅是低8位
    send_uart_response(CMD_GET_AUTO_DELAY, RESP_OK, gAutoModeDelayMs);
    break;

  default:
    // 未知命令
    send_uart_response(cmd, RESP_ERROR, 0);
    break;
  }
}

// 发送UART响应包
void send_uart_response(uint8_t cmd, uint8_t status, uint32_t data) {
  uint8_t respPacket[UART_PACKET_SIZE];

  respPacket[0] = UART_PACKET_HEAD; // 包头
  respPacket[1] = cmd;              // 命令码（回显收到的命令）
  respPacket[2] = status;           // 状态码
  respPacket[3] = (uint8_t)(data & 0xFF);        // 数据字节（低字节）
  respPacket[4] = (uint8_t)((data >> 8) & 0xFF); // 数据字节（次低字节）
  respPacket[5] = (uint8_t)((data >> 16) & 0xFF); // 数据字节（次高字节）
  respPacket[6] = (uint8_t)((data >> 24) & 0xFF); // 数据字节（高字节）
  respPacket[7] = UART_PACKET_TAIL;               // 包尾

  UART_sendDataBlocking(respPacket, UART_PACKET_SIZE);
}

// 发送ADC分析结果
void send_adc_result(AnalysisResult result) {
  // 发送数据包头 - 使用5字节特殊序列
  uint8_t header[8];
  header[0] = 0xAA; // 特殊包头序列开始
  header[1] = 0x55;
  header[2] = 0xA5;
  header[3] = 0x5A;
  header[4] = 0xAA; // 特殊包头序列结束
  header[5] = (uint8_t)(SAMPLE_SIZE & 0xFF);
  header[6] = (uint8_t)((SAMPLE_SIZE >> 8) & 0xFF);
  header[7] = (uint8_t)(NUM_HARMONICS);
  UART_sendDataBlocking(header, 8);

  // 发送ADC原始数据
  UART_sendDataBlocking((uint8_t *)VALID_ADC_DATA, SAMPLE_SIZE * 2);

  // 发送分析结果
  UART_sendHarmonicsAnalysisResultBlocking(&result);

  // 发送数据包尾 - 使用5字节特殊序列
  uint8_t tail[5];
  tail[0] = 0xBB; // 特殊包尾序列开始
  tail[1] = 0x66;
  tail[2] = 0xB6;
  tail[3] = 0x6B;
  tail[4] = 0xBB; // 特殊包尾序列结束
  UART_sendDataBlocking(tail, 5);
}
