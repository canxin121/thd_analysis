#ifndef MYCONSTS_H
#define MYCONSTS_H
#include <ti/iqmath/include/IQmathLib.h>

// 不超过u16
#define SAMPLE_SIZE 1024
#define UART_PACKET_SIZE 8
// 不超过u8
#define NUM_HARMONICS 5
#define CLK_CYCLE_NS 31.25
#define CONVERSION_TIME_NS 187.5

extern const float gHanningWindow[SAMPLE_SIZE];
extern uint16_t gADCRealSamples[SAMPLE_SIZE + 50];
extern uint16_t *VALID_ADC_DATA;
extern uint16_t gADCCLKS;
extern uint8_t gRxPacket[UART_PACKET_SIZE];

// 自动模式下的延时时间(毫秒)，默认1000ms
extern uint16_t gAutoModeDelayMs;

#endif // __CONSTS_H__