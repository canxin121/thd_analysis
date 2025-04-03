#ifndef CUSTOM_INIT
#define CUSTOM_INIT
#include "ti/driverlib/m0p/dl_core.h"
#include "ti_msp_dl_config.h"

SYSCONFIG_WEAK void CUSTOM_SYSCFG_DL_ADC12_0_init(uint16_t adcclks);
SYSCONFIG_WEAK void CUSTOM_SYSCFG_DL_init(uint16_t adcclks);
#endif