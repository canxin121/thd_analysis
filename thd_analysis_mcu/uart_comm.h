#ifndef UART_COMM_H
#define UART_COMM_H

#include "analysis.h"
#include <stdbool.h>
#include <stdint.h>

/**
 * @brief 阻塞式发送数据块
 * @param data 数据指针
 * @param size 数据大小
 */
void UART_sendDataBlocking(const uint8_t *data, uint32_t size);

/**
 * @brief 阻塞式发送字符串
 * @param str 要发送的字符串（必须以null结尾）
 */
void UART_sendStringBlocking(const char *str);

/**
 * @brief 阻塞式发送谐波分析结果
 * @param result 谐波分析结果结构体指针
 */
void UART_sendHarmonicsAnalysisResultBlocking(
    const AnalysisResult *result);

#endif /* UART_COMM_H */