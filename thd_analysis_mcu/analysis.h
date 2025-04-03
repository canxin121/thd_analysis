#ifndef HARMONICS_ANALYSIS_H
#define HARMONICS_ANALYSIS_H

#include "arm_math.h"
#include "consts.h"
#include "stdbool.h"

typedef enum {
  WAVEFORM_NONE, // 无有效波形或未找到基波
  WAVEFORM_DC,   // 直流信号
               // (注意：此实现主要分析交流分量，可能无法完美识别纯直流)
  WAVEFORM_SINE,     // 正弦波
  WAVEFORM_SQUARE,   // 方波
  WAVEFORM_TRIANGLE, // 三角波
  WAVEFORM_SAWTOOTH, // 锯齿波
  WAVEFORM_UNKNOWN   // 未知或无法归类的波形
} WaveformType;

// 谐波分析结果结构体
typedef struct {
  // 4 Byte
  float thd; // 总谐波失真 (%)
  // 4 * NUM_HARMONICS Bytes
  float normalized_harmonics_amplitudes[NUM_HARMONICS]; // 归一化谐波幅度 (Hn / H1),
                                             // [0]是基波(=1.0), [1]是二次,...
  // 4 * NUM_HARMONICS Bytes
  uint32_t harmonic_indices[NUM_HARMONICS]; // 各次谐波在 FFT 频谱中的索引,
                                            // [0]是基波, [1]是二次,...
  // 4 Bytes
  uint32_t fundamental_freq;
  // 1 Byte
  WaveformType waveform; // 检测到的波形类型
  // 1 Byte
  bool has_dc_offset;
  // 可以选择性地添加基波频率 (如果需要计算的话)
  // float fundamental_frequency;
} AnalysisResult;
/**
 * @brief 分析信号谐波并计算总谐波失真
 * @param adc_data ADC采样数据
 * @return 谐波分析结果
 */
AnalysisResult analyze_harmonics(const uint16_t *adc_data);

#endif /* HARMONICS_ANALYSIS_H */
