#include "consts.h"
#include "ti/driverlib/m0p/dl_core.h"
#include "ti_msp_dl_config.h"
#include "utils.h"

// 能保持period_wanted= 5 的极限频率是 22.321kHz
// adcclks上限未知 => 保持能保持period_wanted= 5 的极限频率下限未知
uint16_t calculate_adcclks(uint32_t signal_freq, double period_wanted) {
  if (signal_freq == 0) {
    signal_freq = 1;
  }

  volatile double total_time_ns =
      (double)((uint32_t)1e9 / (uint32_t)signal_freq) / SAMPLE_SIZE *
      period_wanted;

  volatile double sample_time_ns = total_time_ns > CONVERSION_TIME_NS
                                       ? (total_time_ns - CONVERSION_TIME_NS)
                                       : 0;

  volatile uint16_t adcclks = (uint16_t)(sample_time_ns / CLK_CYCLE_NS);

  if (adcclks < 1) {
    adcclks = 1;
  }

  return adcclks;
}

volatile unsigned int delay_times = 0;

// 搭配滴答定时器实现的精确ms延时
void delay_ms(unsigned int ms) {
  delay_times = ms;
  while (delay_times != 0)
    ;
}

void SysTick_Handler(void) {
  if (delay_times != 0) {
    delay_times--;
  }
}