#ifndef COMMAND_H
#define COMMAND_H

#include "analysis.h"
#include <stdint.h>

// 操作模式定义
typedef enum {
  MODE_AUTO = 1,   // 自动模式
  MODE_TRIGGER = 2 // 触发模式
} OperationMode;

// 系统状态机定义（用于检查当前系统是否空闲）
typedef enum {
  STATE_IDLE,     // 空闲状态
  STATE_SAMPLING, // 采样中
  STATE_ANALYZING // 分析中
} SystemState;

// UART命令码定义
#define CMD_SET_AUTO_MODE 0x01    // 设置自动模式
#define CMD_SET_TRIGGER_MODE 0x02 // 设置触发模式
#define CMD_GET_MODE_STATUS 0x03  // 获取当前模式状态
#define CMD_TRIGGER_ONCE 0x04     // 触发一次采样
#define CMD_SET_AUTO_DELAY 0x05   // 设置自动模式延时时间
#define CMD_GET_AUTO_DELAY 0x06   // 获取自动模式延时时间

// UART响应状态码定义
#define RESP_OK 0x00    // 操作成功
#define RESP_ERROR 0x01 // 操作失败
#define RESP_BUSY 0x02  // 系统忙

// UART包头尾
#define UART_PACKET_HEAD 0xAA
#define UART_PACKET_TAIL 0x55

// 函数声明
void process_uart_command(uint8_t *packet, OperationMode *gCurrentMode,
                          SystemState *gSystemState, bool *gTriggerSampling);
void send_uart_response(uint8_t cmd, uint8_t status, uint32_t data);
void send_adc_result(AnalysisResult result);

#endif // COMMAND_H
