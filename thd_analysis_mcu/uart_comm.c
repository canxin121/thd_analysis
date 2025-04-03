#include "uart_comm.h"
#include "analysis.h"
#include "ti/devices/msp/m0p/mspm0g350x.h"
#include "ti/driverlib/m0p/dl_core.h"
#include "ti/driverlib/m0p/sysctl/dl_sysctl_mspm0g1x0x_g3x0x.h"
#include "ti_msp_dl_config.h"
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/cdefs.h>

/**
 * @brief 阻塞式发送单个字符
 * @param c 要发送的字符
 */
static void UART_sendChar(char c) {
  /* 等待发送缓冲区为空 */
  while (!DL_UART_Main_isTXFIFOEmpty(UART_0_INST))
    ;

  /* 发送字符 */
  DL_UART_Main_transmitData(UART_0_INST, c);
}

/**
 * @brief 阻塞式发送数据块
 * @param data 数据指针
 * @param size 数据大小
 */
void UART_sendDataBlocking(const uint8_t *data, uint32_t size) {
  for (uint32_t i = 0; i < size; i++) {
    UART_sendChar(data[i]);
  }
}

/**
 * @brief 阻塞式发送字符串
 * @param str 要发送的字符串
 */
void UART_sendStringBlocking(const char *str) {
  /* 检查字符串是否有效 */
  if (str == NULL) {
    return;
  }

  /* 逐个字符发送 */
  while (*str) {
    UART_sendChar(*str++);
  }
}

/**
 * @brief 阻塞式发送谐波分析结果（逐个字段发送）
 * @param result 谐波分析结果结构体指针
 */
void UART_sendHarmonicsAnalysisResultBlocking(
    const AnalysisResult *result) {
  if (result == NULL) {
    return;
  }

  // 4
  // 发送THD值
  UART_sendDataBlocking((const uint8_t *)&result->thd, sizeof(float));

  // 20
  // 发送归一化谐波幅度数组
  for (int i = 0; i < NUM_HARMONICS; i++) {
    UART_sendDataBlocking((const uint8_t *)&result->normalized_harmonics_amplitudes[i],
                          sizeof(float));
  }

  // 20
  // 发送谐波索引数组
  for (int i = 0; i < NUM_HARMONICS; i++) {
    UART_sendDataBlocking((const uint8_t *)&result->harmonic_indices[i],
                          sizeof(uint32_t));
  }

  // 4
  // 发送基波频率
  UART_sendDataBlocking((const uint8_t *)&result->fundamental_freq,
                        sizeof(uint32_t));
  // 1
  // 发送波形类型
  UART_sendDataBlocking((const uint8_t *)&result->waveform,
                        sizeof(WaveformType));
  // 1
  // 发送直流偏移标志
  UART_sendDataBlocking((const uint8_t *)&result->has_dc_offset, sizeof(bool));

  // UART_sendDataBlocking((uint8_t *)result, sizeof(HarmonicsAnalysisResult));
}
/* 注意：阻塞式发送不需要等待函数，因为发送本身就是阻塞的 */