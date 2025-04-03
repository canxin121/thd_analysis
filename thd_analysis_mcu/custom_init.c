#include "custom_init.h"
#include "consts.h"
#include "ti/driverlib/m0p/dl_core.h"
#include "ti_msp_dl_config.h"
#include "utils.h"

static const DL_ADC12_ClockConfig gADC12_0ClockConfig = {
    .clockSel = DL_ADC12_CLOCK_SYSOSC,
    .divideRatio = DL_ADC12_CLOCK_DIVIDE_1,
    .freqRange = DL_ADC12_CLOCK_FREQ_RANGE_24_TO_32,
};

SYSCONFIG_WEAK void CUSTOM_SYSCFG_DL_ADC12_0_init(uint16_t adcclks) {
  DL_ADC12_setClockConfig(ADC12_0_INST,
                          (DL_ADC12_ClockConfig *)&gADC12_0ClockConfig);
  DL_ADC12_initSingleSample(
      ADC12_0_INST, DL_ADC12_REPEAT_MODE_ENABLED, DL_ADC12_SAMPLING_SOURCE_AUTO,
      DL_ADC12_TRIG_SRC_SOFTWARE, DL_ADC12_SAMP_CONV_RES_12_BIT,
      DL_ADC12_SAMP_CONV_DATA_FORMAT_UNSIGNED);
  DL_ADC12_configConversionMem(
      ADC12_0_INST, ADC12_0_ADCMEM_0, DL_ADC12_INPUT_CHAN_4,
      DL_ADC12_REFERENCE_VOLTAGE_VDDA, DL_ADC12_SAMPLE_TIMER_SOURCE_SCOMP0,
      DL_ADC12_AVERAGING_MODE_DISABLED, DL_ADC12_BURN_OUT_SOURCE_DISABLED,
      DL_ADC12_TRIGGER_MODE_AUTO_NEXT, DL_ADC12_WINDOWS_COMP_MODE_DISABLED);
  DL_ADC12_enableFIFO(ADC12_0_INST);
  DL_ADC12_setPowerDownMode(ADC12_0_INST, DL_ADC12_POWER_DOWN_MODE_MANUAL);
  DL_ADC12_setSampleTime0(ADC12_0_INST, adcclks);
  DL_ADC12_enableDMA(ADC12_0_INST);
  DL_ADC12_setDMASamplesCnt(ADC12_0_INST, 6);
  DL_ADC12_enableDMATrigger(ADC12_0_INST, (DL_ADC12_DMA_MEM10_RESULT_LOADED));
  /* Enable ADC12 interrupt */
  DL_ADC12_clearInterruptStatus(ADC12_0_INST, (DL_ADC12_INTERRUPT_DMA_DONE));
  DL_ADC12_enableInterrupt(ADC12_0_INST, (DL_ADC12_INTERRUPT_DMA_DONE));
  DL_ADC12_enableConversions(ADC12_0_INST);
}

SYSCONFIG_WEAK void CUSTOM_SYSCFG_DL_init(uint16_t adcclks) {
  SYSCFG_DL_initPower();
  SYSCFG_DL_GPIO_init();
  /* Module-Specific Initializations*/
  SYSCFG_DL_SYSCTL_init();
  SYSCFG_DL_UART_0_init();
  CUSTOM_SYSCFG_DL_ADC12_0_init(adcclks);
  SYSCFG_DL_DMA_init();
}
