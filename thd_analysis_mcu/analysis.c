#include "analysis.h"
#include "arm_const_structs.h"
#include "arm_math.h"
#include "consts.h" // 假设包含 SAMPLE_SIZE 和 NUM_HARMONICS
#include "uart_comm.h"
#include <math.h> // 用于 fabsf
#include <stdbool.h>
#include <stdlib.h>
#include <sys/cdefs.h>
#include <ti/iqmath/include/IQmathLib.h>

// --- 常量 ---
#define ADC_MIDPOINT 2048 // ADC 中点值 (12 位 ADC, u12)
#define PRE_FFT_SCALE 16  // 预处理缩放因子 u12 -> u16 (4096 -> 65536)
#define HARMONIC_SEARCH_WINDOW_HALF_WIDTH 2
#define MIN_HARMONIC_THRESHOLD_Q15 100 // 示例值, 需要根据实际信号调整 (Q15)
#define FFT_MAG_SPECTRUM_VALID_LEN (SAMPLE_SIZE / 2 - 1)

// --- 内部辅助函数声明 ---
uint32_t calc_signal_freq(uint32_t adcclks, int16_t fundamental_idx);

static void preprocess_and_prepare_fft(const uint16_t *adc_data,
                                       float adc_data_mean, q15_t *fft_buffer);
static void perform_fft(q15_t *fft_buffer);
static void calculate_magnitude_spectrum(const q15_t *fft_buffer,
                                         q31_t *mag_spectrum);
static bool find_peak_in_window(const q31_t *mag_spectrum,
                                uint32_t search_start, uint32_t search_end,
                                uint32_t *peak_idx, q15_t *peak_val);
static void clear_spectrum_window(q31_t *mag_spectrum, uint32_t center_idx,
                                  uint32_t half_width, uint32_t max_idx);
static bool find_fundamental(const q31_t *mag_spectrum, q15_t threshold,
                             uint32_t *fundamental_idx, q15_t *fundamental_val);
static void find_harmonics(q31_t *mag_spectrum, uint32_t fundamental_idx,
                           q15_t threshold, uint32_t *harmonic_indices,
                           q15_t *harmonic_magnitudes);
static void calculate_results(const q15_t *harmonic_magnitudes_q15,
                              AnalysisResult *result);

static void detect_dc_or_no_signal(const uint16_t *adc_data,
                                   WaveformType *waveform, float *mean_out,
                                   bool *has_dc_offset_out);
static WaveformType detect_waveform_type(const AnalysisResult *result);

// --- 主要分析函数 ---
AnalysisResult analyze_harmonics(const uint16_t *adc_data) {
  AnalysisResult result = {0}; // 初始化结果结构体
  result.thd = 0.0f;
  result.waveform = WAVEFORM_UNKNOWN; // 默认未知
  result.has_dc_offset = false;

  for (int i = 0; i < NUM_HARMONICS; ++i) {
    result.normalized_harmonics_amplitudes[i] = 0.0f;
    result.harmonic_indices[i] = 0;
  }

  // 首先检测是否为直流或者无信号
  WaveformType preliminary_detection = WAVEFORM_UNKNOWN;
  float mean_value = 0.0;
  bool has_dc_offset = false;
  detect_dc_or_no_signal(adc_data, &preliminary_detection, &mean_value,
                         &has_dc_offset);

  result.has_dc_offset = has_dc_offset;

  if (preliminary_detection != WAVEFORM_UNKNOWN) {
    result.waveform = preliminary_detection;
    result.thd = (preliminary_detection == WAVEFORM_NONE) ? -1.0f : 0.0f;
    return result; // 如果是直流或无信号，直接返回，不进行后续分析
  }

  // --- 临时存储 ---
  q15_t harmonic_magnitudes_q15[NUM_HARMONICS] = {0};

  // --- 缓冲区 ---
  static q15_t workspace_buffer[SAMPLE_SIZE * 2] = {0};

  // --- 步骤 1: 数据预处理和 FFT ---
  preprocess_and_prepare_fft(adc_data, mean_value, workspace_buffer);

  perform_fft(workspace_buffer);

  // --- 步骤 2: 计算幅度谱 ---
  calculate_magnitude_spectrum(workspace_buffer, (q31_t *)&workspace_buffer);

  // --- 步骤 3: 查找基波 ---
  uint32_t fundamental_idx = 0;
  q15_t fundamental_val_q15 = 0;
  bool fundamental_found =
      find_fundamental((q31_t *)&workspace_buffer, MIN_HARMONIC_THRESHOLD_Q15,
                       &fundamental_idx, &fundamental_val_q15);

  if (!fundamental_found) {
    result.thd = -1.0f;              // 错误码：未找到有效基波
    result.waveform = WAVEFORM_NONE; // 明确标记为无波形
    return result;
  }

  // 存储基波信息 (Q15 和索引)
  harmonic_magnitudes_q15[0] = fundamental_val_q15;
  result.harmonic_indices[0] = fundamental_idx;

  // --- 步骤 4: 清除基波峰值周围的窗口 ---
  clear_spectrum_window((q31_t *)&workspace_buffer, fundamental_idx,
                        HARMONIC_SEARCH_WINDOW_HALF_WIDTH,
                        FFT_MAG_SPECTRUM_VALID_LEN);

  // --- 步骤 5: 查找谐波 ---
  find_harmonics((q31_t *)&workspace_buffer, fundamental_idx,
                 MIN_HARMONIC_THRESHOLD_Q15, result.harmonic_indices,
                 harmonic_magnitudes_q15);

  // --- 步骤 6: 计算最终结果 (THD 和归一化幅度) ---
  calculate_results(harmonic_magnitudes_q15, &result);

  // --- 步骤 8: 检测波形类型 ---
  result.waveform = detect_waveform_type(&result);

  // --- 步骤 9：计算基波频率
  result.fundamental_freq = calc_signal_freq(gADCCLKS, fundamental_idx);

  return result;
}

// --- 内部辅助函数实现 ---
uint32_t calc_signal_freq(uint32_t adcclks, int16_t fundamental_idx) {
  volatile double adcclks_double = adcclks;
  volatile double sample_time_ns = (double)adcclks_double * CLK_CYCLE_NS;
  volatile double total_time_ns = sample_time_ns + CONVERSION_TIME_NS;
  volatile double fs = 1e9 / total_time_ns;
  volatile double f_resolution = fs / SAMPLE_SIZE;
  volatile double f = f_resolution * (double)fundamental_idx;
  return (uint32_t)f;
}

/**
 * @brief 对 ADC 数据进行预处理、加窗，并准备 FFT 输入缓冲区。
 */
static void preprocess_and_prepare_fft(const uint16_t *adc_data,
                                       float adc_data_mean, q15_t *fft_buffer) {
  const _iq16 scale_iq = _IQ16(PRE_FFT_SCALE);
  for (uint32_t i = 0; i < SAMPLE_SIZE; i++) {
    // 1. 减去直流偏置 (ADC 中点) 并转换为 IQ
    int32_t current = (float)adc_data[i] - adc_data_mean;
    // 2. 缩放
    _iq16 scaled = _IQ16mpy(_IQ16(current), scale_iq);
    // 3. 加窗 (Hanning 窗) - 假设 gHanningWindow 是 _iq 格式
    int16_t windowed =
        (int16_t)_IQ16toF(_IQ16mpy(scaled, _IQ16(gHanningWindow[i])));

    fft_buffer[i] = windowed; // 纯实数FFT，直接存储实数数据
  }
}

/**
 * @brief 执行 Q15 定点实数 FFT。
 */
static void perform_fft(q15_t *fft_buffer) {
  // 根据 SAMPLE_SIZE 选择合适的 CMSIS RFFT 实例
#if SAMPLE_SIZE == 1024
  arm_rfft_instance_q15 rfft_instance;
  arm_rfft_init_q15(&rfft_instance, SAMPLE_SIZE, 0, 1);
  arm_rfft_q15(&rfft_instance, fft_buffer, fft_buffer);
#elif SAMPLE_SIZE == 512
  arm_rfft_instance_q15 rfft_instance;
  arm_rfft_init_q15(&rfft_instance, SAMPLE_SIZE, 0, 1);
  arm_rfft_q15(&rfft_instance, fft_buffer, fft_buffer);
#elif SAMPLE_SIZE == 256
  arm_rfft_instance_q15 rfft_instance;
  arm_rfft_init_q15(&rfft_instance, SAMPLE_SIZE, 0, 1);
  arm_rfft_q15(&rfft_instance, fft_buffer, fft_buffer);
#else
#error                                                                         \
    "Unsupported SAMPLE_SIZE for arm_rfft_q15. Check consts.h and CMSIS-DSP lib."
#endif
}

// --- 修改幅度谱计算函数 ---
/**
 * @brief 计算实数FFT输出的幅度谱(Q31格式)
 * @param fft_buffer FFT输出缓冲区(q15_t格式)
 * @param mag_spectrum 输出的幅度谱(q31_t格式)
 * @note 手动计算以提高精度，使用32位运算避免溢出
 */
static void calculate_magnitude_spectrum(const q15_t *fft_buffer,
                                         q31_t *mag_spectrum) {
  // FFT输出是复数形式(实部+虚部交替存储)
  for (uint32_t i = 0; i < SAMPLE_SIZE / 2; i++) {
    // 获取实部和虚部(转换为q31_t避免计算溢出)
    q31_t real = (q31_t)fft_buffer[2 * i];
    q31_t imag = (q31_t)fft_buffer[2 * i + 1];

    // __BKPT();
    // 计算平方和(使用64位中间结果防止溢出)
    int64_t real_sq = (int64_t)real * real;
    int64_t imag_sq = (int64_t)imag * imag;
    int64_t sum_sq = real_sq + imag_sq;
    // __BKPT();

    // 计算平方根(近似计算)
    // 可以使用ARM的平方根函数或自定义近似算法
    q31_t magnitude = (q31_t)sqrt(sum_sq);

    // __BKPT();
    // 存储结果
    mag_spectrum[i] = magnitude;
  }
}
/**
 * @brief 在幅度谱的指定窗口内查找最大峰值。
 */
static bool find_peak_in_window(const q31_t *mag_spectrum,
                                uint32_t search_start, uint32_t search_end,
                                uint32_t *peak_idx, q15_t *peak_val) {
  // 确保窗口索引有效且不为 0 (跳过直流)
  search_start = (search_start == 0) ? 1 : search_start;
  if (search_start > search_end || search_start >= SAMPLE_SIZE / 2) {
    *peak_idx = 0;
    *peak_val = 0;
    return false; // 无效窗口
  }

  // 限制搜索结束索引不超过有效范围 (最大索引是 SAMPLE_SIZE / 2 - 1)
  if (search_end >= SAMPLE_SIZE / 2) {
    search_end = SAMPLE_SIZE / 2 - 1;
  }

  // 确保窗口至少有一个点
  if (search_start > search_end) {
    *peak_idx = 0;
    *peak_val = 0;
    return false;
  }

  uint32_t window_len = search_end - search_start + 1;
  uint32_t local_max_idx = 0; // arm_max_q15 返回的是窗口内的相对索引
  q31_t max_val = 0;
  arm_status status;

  // 在指定窗口内查找最大值
  arm_max_q31(mag_spectrum + search_start, // 指向窗口起始位置
              window_len,                  // 窗口长度
              &max_val,                    // 输出：最大值
              &local_max_idx); // 输出：最大值在窗口内的索引 (0 to window_len-1)

  // 如果找到的最大值大于 0 (意味着窗口内有非零值)
  // 注意：阈值检查在调用此函数之后进行
  if (max_val > 0) {
    *peak_val = max_val;
    *peak_idx = search_start + local_max_idx; // 计算绝对索引
    return true;
  } else {
    *peak_idx = 0;
    *peak_val = 0;
    return false; // 窗口内没有找到峰值 (可能已被清零或全为零)
  }
}

/**
 * @brief 清除幅度谱中指定索引周围的一个窗口。
 */
static void clear_spectrum_window(q31_t *mag_spectrum, uint32_t center_idx,
                                  uint32_t half_width, uint32_t max_idx) {
  if (center_idx == 0 || center_idx > max_idx)
    return; // 不清除直流或无效中心

  // 计算窗口的实际起始和结束索引，并进行边界检查
  uint32_t start =
      (center_idx > half_width) ? (center_idx - half_width) : 1; // 最小为 1
  uint32_t end = center_idx + half_width;

  // 确保结束索引不超过最大有效索引
  if (end > max_idx) {
    end = max_idx;
  }

  // 清零窗口内的幅度值
  if (start <= end) { // 确保窗口有效
    // 使用 CMSIS-DSP 的 arm_fill_q15 进行优化
    uint32_t num_elements_to_clear = end - start + 1;
    if (num_elements_to_clear > 0) {
      arm_fill_q31(0, mag_spectrum + start, num_elements_to_clear);
    }
  }
}

/**
 * @brief 查找基波频率分量。
 */
static bool find_fundamental(const q31_t *mag_spectrum, q15_t threshold,
                             uint32_t *fundamental_idx,
                             q15_t *fundamental_val) {
  // 搜索范围从索引 1 到 SAMPLE_SIZE / 2 - 1 (FFT_MAG_SPECTRUM_VALID_LEN)
  uint32_t search_len = FFT_MAG_SPECTRUM_VALID_LEN;
  *fundamental_idx = 0; // 初始化
  *fundamental_val = 0; // 初始化

  if (search_len == 0)
    return false; // 没有可搜索的区域

  uint32_t max_idx_relative = 0; // 结果是相对于搜索起点的索引
  q31_t max_val = 0;
  arm_status status;

  // 在 mag_spectrum[1] 到 mag_spectrum[SAMPLE_SIZE/2 - 1] 范围内查找最大值
  arm_max_q31(mag_spectrum + 1, // 从索引 1 开始搜索
              search_len,       // 搜索长度
              &max_val,         // 输出：最大值
              &max_idx_relative); // 输出：最大值在搜索范围内的相对索引

  // 将相对索引转换为绝对索引 (相对于 mag_spectrum 的开始)
  // 因为搜索从索引 1 开始，所以绝对索引是 relative + 1
  *fundamental_idx = max_idx_relative + 1;
  *fundamental_val = max_val;

  // 检查找到的峰值是否满足阈值且索引有效
  if (*fundamental_val >= threshold && *fundamental_idx > 0 &&
      *fundamental_idx <= FFT_MAG_SPECTRUM_VALID_LEN) {
    return true; // 找到有效的基波
  }

  // 未找到满足条件的基波
  *fundamental_idx = 0;
  *fundamental_val = 0;
  return false;
}

/**
 * @brief 查找各次谐波分量。
 */
static void
find_harmonics(q31_t *mag_spectrum, // 注意：此函数会修改 mag_spectrum
               uint32_t fundamental_idx, q15_t threshold,
               uint32_t *harmonic_indices, // 输出
               q15_t *harmonic_magnitudes) // 输出
{
  // 假设 harmonic_indices[0] 和 harmonic_magnitudes[0] 已被填充为基波信息

  // 从二次谐波开始查找 (n=2), 直到 NUM_HARMONICS
  for (uint8_t n = 2; n <= NUM_HARMONICS; n++) {
    int harmonic_array_index =
        n - 1; // 在结果数组中的索引 (H2 存在 index 1, H3 存 index 2...)

    // 1. 计算谐波的期望频率索引 (理想位置)
    uint32_t expected_idx = n * fundamental_idx;

    // 2. 检查期望索引是否超出有效范围 (FFT_MAG_SPECTRUM_VALID_LEN)
    if (expected_idx > FFT_MAG_SPECTRUM_VALID_LEN) {
      harmonic_magnitudes[harmonic_array_index] = 0;
      harmonic_indices[harmonic_array_index] =
          expected_idx; // 仍然保存理论索引位置
      continue; // 超出范围，该谐波及其更高次谐波都无法查找
    }

    // 3. 定义搜索窗口 [search_start, search_end]
    uint32_t search_start =
        (expected_idx > HARMONIC_SEARCH_WINDOW_HALF_WIDTH)
            ? (expected_idx - HARMONIC_SEARCH_WINDOW_HALF_WIDTH)
            : 1; // 最小从索引 1 开始
    uint32_t search_end = expected_idx + HARMONIC_SEARCH_WINDOW_HALF_WIDTH;
    // 再次确保 search_end 不超过最大有效索引
    if (search_end > FFT_MAG_SPECTRUM_VALID_LEN) {
      search_end = FFT_MAG_SPECTRUM_VALID_LEN;
    }
    // 确保 start <= end
    if (search_start > search_end) {
      search_start = search_end; // 如果窗口宽度导致 start > end，让它们相等
    }

    // 4. 在窗口内查找最大峰值
    uint32_t found_peak_idx = 0;
    q15_t found_peak_val = 0;
    bool peak_found_in_window =
        find_peak_in_window(mag_spectrum, search_start, search_end,
                            &found_peak_idx, &found_peak_val);

    // 5. 检查找到的峰值是否满足阈值
    if (peak_found_in_window && found_peak_val >= threshold) {
      // 存储找到的谐波信息
      harmonic_magnitudes[harmonic_array_index] = found_peak_val;
      harmonic_indices[harmonic_array_index] = found_peak_idx;

      // 6. 清除该谐波所在搜索窗口的幅度谱，防止干扰更高次谐波查找
      //    使用期望索引作为中心进行清除
      clear_spectrum_window(mag_spectrum, expected_idx,
                            HARMONIC_SEARCH_WINDOW_HALF_WIDTH,
                            FFT_MAG_SPECTRUM_VALID_LEN);
    } else {
      // 未找到满足条件的谐波峰值，但仍记录理论谐波位置
      harmonic_magnitudes[harmonic_array_index] = 0;
      harmonic_indices[harmonic_array_index] =
          expected_idx; // 使用理论期望位置而不是0
      // 注意：这里不清除窗口，因为没有确认找到目标谐波
    }
  } // 结束谐波查找循环
}

/**
 * @brief 计算总谐波失真 (THD) 和归一化的谐波幅度。
 */
static void calculate_results(const q15_t *harmonic_magnitudes_q15,
                              AnalysisResult *result) {
  // 将基波幅度从 Q15 转换为 IQ 格式
  _iq fundamental_val_iq = _Q15toIQ(harmonic_magnitudes_q15[0]);

  // 检查基波幅度是否有效 (大于 0)
  if (fundamental_val_iq <= _IQ(0.0)) {
    result->thd = -2.0f; // 错误码：基波幅度无效或为零
    // 归一化谐波保持为 0 (已在 analyze_harmonics 中初始化)
    return;
  }

  // --- 计算 THD ---
  _iq harmonics_sq_sum_iq = _IQ(0.0); // 初始化谐波平方和 (IQ 格式)

  // 累加各次谐波幅度的平方 (从二次谐波开始, index=1)
  for (uint8_t i = 1; i < NUM_HARMONICS; i++) {
    q15_t current_harmonic_q15 = harmonic_magnitudes_q15[i];
    if (current_harmonic_q15 > 0) {
      _iq harmonic_val_iq = _Q15toIQ(current_harmonic_q15);
      _iq harmonic_sq_iq = _IQmpy(harmonic_val_iq, harmonic_val_iq);
      // 考虑潜在的溢出，进行累加
      // 简单的累加，如果 IQmath 范围足够大
      harmonics_sq_sum_iq += harmonic_sq_iq;
      // 或者使用饱和累加 (如果担心溢出，需要定义 IQ_MAX, IQ_MIN)
      // harmonics_sq_sum_iq = _IQsat(harmonics_sq_sum_iq + harmonic_sq_iq,
      // IQ_MAX, IQ_MIN);
    }
  }

  _iq thd_numerator_iq = _IQ(0.0);
  if (harmonics_sq_sum_iq > _IQ(0.0)) {
    // 计算谐波平方和的平方根
    // 检查参数是否为负，虽然理论上平方和不应为负
    if (harmonics_sq_sum_iq < 0)
      harmonics_sq_sum_iq = _IQ(0.0);
    thd_numerator_iq = _IQsqrt(harmonics_sq_sum_iq);
  }

  // 计算 THD 比率 (RMS_Harmonics / Fundamental)
  // 使用安全的除法，防止除以零 (虽然前面检查过 fundamental_val_iq > 0)
  _iq thd_ratio_iq = _IQdiv(thd_numerator_iq, fundamental_val_iq);

  // 转换为百分比
  _iq hundred_iq = _IQ(100.0);
  _iq thd_percent_iq = _IQmpy(thd_ratio_iq, hundred_iq);

  // 将最终 THD (IQ 格式) 转换为浮点数并存储
  result->thd = _IQtoF(thd_percent_iq);

  // --- 计算归一化谐波幅度 ---
  result->normalized_harmonics_amplitudes[0] = 1.0f; // 基波 H1/H1 = 1.0

  for (uint8_t i = 1; i < NUM_HARMONICS; i++) {
    q15_t current_harmonic_q15 = harmonic_magnitudes_q15[i];
    if (current_harmonic_q15 > 0) {
      _iq harmonic_val_iq = _Q15toIQ(current_harmonic_q15);
      // 计算归一化幅度 (Hn / H1)
      _iq norm_harmonic_iq = _IQdiv(harmonic_val_iq, fundamental_val_iq);
      // 转换为浮点数并存储
      result->normalized_harmonics_amplitudes[i] = _IQtoF(norm_harmonic_iq);
    } else {
      result->normalized_harmonics_amplitudes[i] = 0.0f;
    }
  }
}

// --- 直流/无信号检测参数 ---
#define DC_SIGNAL_VARIANCE_THRESHOLD 500.0f // 方差小于此值认为是直流信号
#define NO_SIGNAL_MEAN_THRESHOLD 200.0f // 均值与ADC中点的差值小于此值认为无信号

/**
 * @brief 通过计算均值和方差检测直流信号或无信号
 * @param adc_data 输入的ADC数据数组
 * @return 检测结果: WAVEFORM_DC(直流), WAVEFORM_NONE(无信号),
 * WAVEFORM_UNKNOWN(需要进一步分析)
 */
static void detect_dc_or_no_signal(const uint16_t *adc_data,
                                   WaveformType *waveform, float *mean_out,
                                   bool *has_dc_offset_out) {
  uint32_t i;
  float sum = 0.0f;
  float sum_sq = 0.0f;
  float mean, variance;

  // 1. 计算均值
  for (i = 0; i < SAMPLE_SIZE; i++) {
    sum += (float)adc_data[i];
  }
  mean = sum / SAMPLE_SIZE;

  // 2. 计算方差
  for (i = 0; i < SAMPLE_SIZE; i++) {
    float diff = (float)adc_data[i] - mean;
    sum_sq += diff * diff;
  }
  variance = sum_sq / SAMPLE_SIZE;
  // 是由有直流偏置
  bool has_dc_offset = fabsf(mean - ADC_MIDPOINT) > NO_SIGNAL_MEAN_THRESHOLD;
  // 信号基本是直线
  if (variance < DC_SIGNAL_VARIANCE_THRESHOLD) {
    // 信号均值基本是2048
    if (has_dc_offset) {
      *waveform = WAVEFORM_DC;
    } else {
      *waveform = WAVEFORM_NONE;
    }
  } else {
    *waveform = WAVEFORM_UNKNOWN;
  }

  *has_dc_offset_out = has_dc_offset;
  *mean_out = mean;
}

/**
 * @brief 根据谐波分析结果检测波形类型（基于标准波形谐波特征表）
 * @param result 指向包含归一化谐波幅度的结果结构体指针
 * @return 检测到的波形类型
 */
static WaveformType detect_waveform_type(const AnalysisResult *result) {
  float h2 = result->normalized_harmonics_amplitudes[1]; // 2次谐波
  float h3 = result->normalized_harmonics_amplitudes[2]; // 3次谐波
  float h4 = result->normalized_harmonics_amplitudes[3]; // 4次谐波
  float h5 = result->normalized_harmonics_amplitudes[4]; // 5次谐波

  /* 1. 正弦波判断:
   *    H2, H3, H4, H5 => [0.0, 0.03]
   */
  if (fabsf(h2) < 0.03f && fabsf(h3) < 0.03f && fabsf(h4) < 0.03f &&
      fabsf(h5) < 0.03f) {
    return WAVEFORM_SINE;
  }

  /* 2. 三角波判断：
   *    H2 => [0.0, 0.03],
   *    H3 => [0.08, 0.14],
   *    H4 => [0.0, 0.03],
   *    H5 => [0.00, 0.05]
   */
  if (fabsf(h2) < 0.03f && (h3 >= 0.08f && h3 <= 0.14f) && fabsf(h4) < 0.03f &&
      (h5 >= 0.0f && h5 <= 0.05f)) {
    return WAVEFORM_TRIANGLE;
  }

  /* 3. 方波判断：
   *    H2 => [0.0, 0.03],
   *    H3 => [0.30, 0.36],
   *    H4 => [0.0, 0.03],
   *    H5 => [0.0, 0.25]
   */
  if (fabsf(h2) < 0.03f && (h3 >= 0.30f && h3 <= 0.36f) && fabsf(h4) < 0.03f &&
      (h5 >= 0.0f && h5 <= 0.25f)) {
    return WAVEFORM_SQUARE;
  }

  /* 4. 锯齿波判断：
   *    H2 => [0.45, 0.55],
   *    H3 => [0.30, 0.36],
   *    H4 => [0.23, 0.27],
   *    H5 => [0.0, 0.22]
   */
  if ((h2 >= 0.45f && h2 <= 0.55f) && (h3 >= 0.30f && h3 <= 0.36f) &&
      (h4 >= 0.23f && h4 <= 0.27f) && (h5 >= 0.0f && h5 <= 0.22f)) {
    return WAVEFORM_SAWTOOTH;
  }

  // 未匹配任何特征
  return WAVEFORM_UNKNOWN;
}