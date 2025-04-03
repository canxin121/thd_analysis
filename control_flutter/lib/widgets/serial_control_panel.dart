import 'package:flutter/material.dart';
import '../controllers/serial_controller.dart';

class SerialControlPanel extends StatelessWidget {
  final SerialController controller;
  final bool isLandscape;

  const SerialControlPanel({
    super.key,
    required this.controller,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child:
          isLandscape
              ? _buildLandscapeControlPanel()
              : _buildPortraitControlPanel(),
    );
  }

  // 横屏模式控制面板
  Widget _buildLandscapeControlPanel() {
    return Row(
      children: [
        const SizedBox(width: 8),
        const Text('串口:'),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: controller.selectedPort,
            hint: const Text('选择串口'),
            onChanged:
                controller.isConnected
                    ? null
                    : (String? newValue) {
                      controller.setSelectedPort(newValue);
                    },
            items:
                controller.availablePorts.map<DropdownMenuItem<String>>((
                  String value,
                ) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: controller.refreshPorts,
          tooltip: '刷新串口列表',
        ),
        const SizedBox(width: 8),
        if (controller.isConnecting)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          ElevatedButton(
            onPressed: controller.toggleConnection,
            child: Text(controller.isConnected ? '断开' : '连接'),
          ),
        const SizedBox(width: 16),
        if (controller.isConnected)
          Expanded(
            child:
                controller.autoTrigger
                    ? _buildAutoTriggerControls()
                    : _buildManualTriggerControls(),
          ),
      ],
    );
  }

  // 竖屏模式控制面板
  Widget _buildPortraitControlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 第一行：串口选择和连接
        Row(
          children: [
            const SizedBox(width: 8),
            const Text('串口:'),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: controller.selectedPort,
                hint: const Text('选择串口'),
                onChanged:
                    controller.isConnected
                        ? null
                        : (String? newValue) {
                          controller.setSelectedPort(newValue);
                        },
                items:
                    controller.availablePorts.map<DropdownMenuItem<String>>((
                      String value,
                    ) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: controller.refreshPorts,
              tooltip: '刷新串口列表',
            ),
            const SizedBox(width: 8),
            if (controller.isConnecting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ElevatedButton(
                onPressed: controller.toggleConnection,
                child: Text(controller.isConnected ? '断开' : '连接'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 第二行：触发控制
        if (controller.isConnected)
          Row(
            children: [
              Expanded(
                child:
                    controller.autoTrigger
                        ? _buildAutoTriggerControls()
                        : _buildManualTriggerControls(),
              ),
            ],
          ),
      ],
    );
  }

  // 构建自动触发控制区
  Widget _buildAutoTriggerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('自动触发: ${controller.triggerInterval} ms'),
        const SizedBox(width: 8),
        Builder(
          builder:
              (context) => IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showIntervalDialog(context),
                tooltip: '设置触发间隔',
              ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: controller.toggleAutoTrigger,
          child: const Text('停止自动'),
        ),
      ],
    );
  }

  // 构建手动触发控制区
  Widget _buildManualTriggerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton(
          onPressed: controller.toggleAutoTrigger,
          child: const Text('启动自动'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: controller.isLoading ? null : controller.triggerSample,
          child:
              controller.isLoading
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('触发采样'),
        ),
      ],
    );
  }

  // 显示设置触发间隔的对话框
  void _showIntervalDialog(BuildContext context) {
    final textController = TextEditingController(
      text: controller.triggerInterval.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置触发间隔'),
          content: TextField(
            controller: textController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '触发间隔 (毫秒)',
              hintText: '输入500-10000之间的值',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = int.tryParse(textController.text);
                if (value != null && value >= 500 && value <= 10000) {
                  controller.setTriggerInterval(value);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
