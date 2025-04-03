import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/serial_controller.dart';
import '../waveform_utils.dart';
import '../widgets/waveform_chart.dart';
import '../widgets/analysis_result_display.dart';
import '../widgets/serial_control_panel.dart';

class MyHomePage extends StatelessWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<SerialController>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = isLandscapeMode(screenWidth);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title),
      ),
      body: Column(
        children: [
          // 串口控制面板
          SerialControlPanel(controller: controller, isLandscape: isLandscape),

          // 错误消息显示
          if (controller.errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.errorMessage,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: controller.clearErrorMessage,
                    color: Colors.red.shade700,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // 主内容区域 - 根据屏幕宽度选择布局方向
          Expanded(
            child:
                isLandscape
                    ? _buildLandscapeContentLayout(controller)
                    : _buildPortraitContentLayout(controller, context),
          ),
        ],
      ),
    );
  }

  // 横屏模式内容布局
  Widget _buildLandscapeContentLayout(SerialController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 波形图
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '波形图',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: WaveformChart(
                    analysisResult: controller.analysisResult,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 分析结果
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '分析结果',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: AnalysisResultDisplay(
                    analysisResult: controller.analysisResult,
                    useInternalScroll: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 竖屏模式内容布局
  Widget _buildPortraitContentLayout(
    SerialController controller,
    BuildContext context,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 波形图 - 设置固定高度
          Container(
            height: MediaQuery.of(context).size.height * 0.4, // 屏幕高度的40%
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '波形图',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: WaveformChart(
                    analysisResult: controller.analysisResult,
                  ),
                ),
              ],
            ),
          ),

          // 分析结果 - 不使用内部滚动，高度自适应内容
          Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text(
                    '分析结果',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                AnalysisResultDisplay(
                  analysisResult: controller.analysisResult,
                  useInternalScroll: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
