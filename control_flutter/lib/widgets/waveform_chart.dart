import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../types/adc_data_analysis.dart';

class WaveformChart extends StatelessWidget {
  final AdcDataAndAnalysisResult? analysisResult;

  const WaveformChart({super.key, required this.analysisResult});

  @override
  Widget build(BuildContext context) {
    if (analysisResult == null) {
      return const Center(child: Text('暂无波形数据'));
    }

    final adcData = analysisResult!.adcData;
    final spots = <FlSpot>[];

    // 转换ADC数据为图表点
    for (int i = 0; i < adcData.data.length; i++) {
      spots.add(FlSpot(i.toDouble(), adcData.data[i].toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withAlpha((255.0 * 0.3).round()),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey.withAlpha((255.0 * 0.3).round()),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: adcData.data.length / 5,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${value.toInt()}'),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 1000,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${value.toInt()}'),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: Colors.grey.withAlpha((255.0 * 0.5).round()),
          ),
        ),
        minX: 0,
        maxX: adcData.data.length.toDouble() - 1,
        minY: 0,
        maxY: 4095, // 12位ADC的最大值
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.blue,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }
}
