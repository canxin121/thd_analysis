#ifndef UTILS
#define UTILS
#include "consts.h"
#include "ti/driverlib/m0p/dl_core.h"
#include "ti_msp_dl_config.h"

uint16_t calculate_adcclks(uint32_t signal_freq, double period_wanted);

void delay_ms(unsigned int ms);

#endif