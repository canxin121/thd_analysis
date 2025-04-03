#include "analysis.h"
#include "arm_const_structs.h"
#include "arm_math.h"
#include "command.h" // 添加命令处理模块头文件
#include "consts.h"
#include "custom_init.h"
#include "ti/driverlib/dl_adc12.h"
#include "ti/driverlib/m0p/dl_core.h"
#include "ti_msp_dl_config.h"
#include "uart_comm.h"
#include "utils.h"
#include <sys/cdefs.h>

// adc dma已设置为自动触发
// 进入adc中断后, 不会自动关闭Conversion, 需要手动关闭, 否则会一直采集并触发中断
// 当手动关闭后, 如果想再次开启, 需要先调用enableConversions,
// 然后再调用startConversion才会继续采集并触发下一个adc中断

// uart 进入中断后需要手动重新配置DMA通道, 才能继续接收数据并触发中断

// 全局变量
SystemState gSystemState = STATE_IDLE;     // 当前系统状态
OperationMode gCurrentMode = MODE_TRIGGER; // 默认触发模式
bool gTriggerSampling = false;             // 触发采样标志
volatile bool gUARTCommandReady = false;   // 新增：UART命令接收标志

int main(void) {
  // 根据要采集的信号的频率来初始化
  CUSTOM_SYSCFG_DL_init(gADCCLKS);
  DL_SYSCTL_disableSleepOnExit();

  // ADC
  // 默认是触发模式，不自动启动ADC
  DL_DMA_setSrcAddr(DMA, DMA_CH0_CHAN_ID,
                    (uint32_t)DL_ADC12_getFIFOAddress(ADC12_0_INST));
  DL_DMA_setDestAddr(DMA, DMA_CH0_CHAN_ID, (uint32_t)gADCRealSamples);
  DL_DMA_setTransferSize(DMA, DMA_CH0_CHAN_ID, ((SAMPLE_SIZE + 50) >> 1));
  DL_DMA_enableChannel(DMA, DMA_CH0_CHAN_ID);
  NVIC_EnableIRQ(ADC12_0_INST_INT_IRQN);

  // UART
  DL_DMA_setSrcAddr(DMA, DMA_CH1_CHAN_ID, (uint32_t)(&UART_0_INST->RXDATA));
  DL_DMA_setDestAddr(DMA, DMA_CH1_CHAN_ID, (uint32_t)&gRxPacket[0]);
  DL_DMA_setTransferSize(DMA, DMA_CH1_CHAN_ID, UART_PACKET_SIZE);
  DL_DMA_enableChannel(DMA, DMA_CH1_CHAN_ID);
  NVIC_EnableIRQ(UART_0_INST_INT_IRQN);

  while (1) {
    // 若有UART命令待处理，则在状态机之外统一调用处理
    // 并且处理完成之后再去重新配置DMA通道
    // 以便接收下一个命令
    if (gUARTCommandReady && gSystemState == STATE_IDLE) {
      process_uart_command(gRxPacket, &gCurrentMode, &gSystemState,
                           &gTriggerSampling);
      DL_DMA_setDestAddr(DMA, DMA_CH1_CHAN_ID, (uint32_t)&gRxPacket[0]);
      DL_DMA_setTransferSize(DMA, DMA_CH1_CHAN_ID, UART_PACKET_SIZE);
      DL_DMA_enableChannel(DMA, DMA_CH1_CHAN_ID);
      gUARTCommandReady = false;
    }

    // 状态机实现
    switch (gSystemState) {
    case STATE_IDLE:
      // 在空闲状态检查是否需要开始采样
      if (gCurrentMode == MODE_AUTO || gTriggerSampling) {
        // 启动ADC采样
        DL_ADC12_enableConversions(ADC12_0_INST);
        DL_ADC12_startConversion(ADC12_0_INST);
        gSystemState = STATE_SAMPLING;

        // 如果是触发模式，重置触发标志
        if (gTriggerSampling) {
          gTriggerSampling = false;
        }
      }
      break;

    case STATE_SAMPLING:
      // ADC正在采样，等待中断完成
      // 由ADC中断处理函数更新状态
      break;

    case STATE_ANALYZING: {
      // 分析ADC数据
      AnalysisResult result = analyze_harmonics(VALID_ADC_DATA);
      uint16_t adcclks_output = calculate_adcclks(result.fundamental_freq, 5.0);
      if (gADCCLKS != adcclks_output) {
        gADCCLKS = adcclks_output;
        CUSTOM_SYSCFG_DL_ADC12_0_init(adcclks_output);

        // 启动ADC采样
        DL_ADC12_enableConversions(ADC12_0_INST);
        DL_ADC12_startConversion(ADC12_0_INST);
        break;
      }

      // 发送分析结果
      send_adc_result(result);

      // 根据模式决定下一步操作
      if (gCurrentMode == MODE_AUTO) {
        // 自动模式：使用可配置延时后回到空闲状态，将自动开始下一次采样
        delay_ms(gAutoModeDelayMs);
      }
      // 不管哪种模式，都回到空闲状态
      gSystemState = STATE_IDLE;
      break;
    }
    }

    __WFI();
  }
}

void ADC12_0_INST_IRQHandler(void) {
  if (DL_ADC12_getPendingInterrupt(ADC12_0_INST) == DL_ADC12_IIDX_DMA_DONE) {
    // 清除中断标志
    DL_ADC12_clearInterruptStatus(ADC12_0_INST, DL_ADC12_IIDX_DMA_DONE);
    // 禁用ADC转换，防止数据在分析期间继续采集导致覆盖
    DL_ADC12_disableConversions(ADC12_0_INST);

    // 更新状态为分析阶段
    if (gSystemState == STATE_SAMPLING) {
      gSystemState = STATE_ANALYZING;
    }
  }
}

void UART_0_INST_IRQHandler(void) {
  switch (DL_UART_Main_getPendingInterrupt(UART_0_INST)) {
  case DL_UART_MAIN_IIDX_DMA_DONE_RX:
    DL_UART_clearInterruptStatus(UART_0_INST, DL_UART_INTERRUPT_DMA_DONE_RX);
    gUARTCommandReady = true;
    break;
  default:
    break;
  }
}