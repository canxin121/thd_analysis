import 'package:flutter/material.dart';

class SerialControlPanel extends StatelessWidget {
  final List<String> availablePorts;
  final String? selectedPort;
  final bool isConnected;
  final bool isConnecting;
  final bool autoTrigger;
  final int triggerInterval;
  final bool isLoading;
  final bool isLandscape;
  final BuildContext context;

  final VoidCallback onRefreshPorts;
  final Function(String?) onSetSelectedPort;
  final VoidCallback onToggleConnection;
  final VoidCallback onToggleAutoTrigger;
  final VoidCallback onTriggerSample;
  final Function(int) onSetTriggerInterval;
  final VoidCallback onShowConfig;

  const SerialControlPanel({
    super.key,
    required this.availablePorts,
    required this.selectedPort,
    required this.isConnected,
    required this.isConnecting,
    required this.autoTrigger,
    required this.triggerInterval,
    required this.isLoading,
    required this.isLandscape,
    required this.onRefreshPorts,
    required this.onSetSelectedPort,
    required this.onToggleConnection,
    required this.onToggleAutoTrigger,
    required this.onTriggerSample,
    required this.onSetTriggerInterval,
    required this.context,
    required this.onShowConfig,
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
            value: selectedPort,
            hint: const Text('选择串口'),
            onChanged:
                isConnected
                    ? null
                    : (String? newValue) {
                      onSetSelectedPort(newValue);
                    },
            items:
                availablePorts.map<DropdownMenuItem<String>>((String value) {
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
          onPressed: onRefreshPorts,
          tooltip: '刷新串口列表',
        ),
        const SizedBox(width: 8),
        // 添加配置按钮
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: isConnecting ? null : onShowConfig,
          tooltip: '串口配置',
        ),
        const SizedBox(width: 8),
        if (isConnecting)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          ElevatedButton(
            onPressed: onToggleConnection,
            child: Text(isConnected ? '断开' : '连接'),
          ),
        const SizedBox(width: 16),
        if (isConnected)
          Expanded(
            child:
                autoTrigger
                    ? _buildAutoTriggerControls(context)
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
                value: selectedPort,
                hint: const Text('选择串口'),
                onChanged:
                    isConnected
                        ? null
                        : (String? newValue) {
                          onSetSelectedPort(newValue);
                        },
                items:
                    availablePorts.map<DropdownMenuItem<String>>((
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
              onPressed: onRefreshPorts,
              tooltip: '刷新串口列表',
            ),
            const SizedBox(width: 8),
            // 添加配置按钮
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: isConnecting ? null : onShowConfig,
              tooltip: '串口配置',
            ),
            const SizedBox(width: 8),
            if (isConnecting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ElevatedButton(
                onPressed: onToggleConnection,
                child: Text(isConnected ? '断开' : '连接'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 第二行：触发控制
        if (isConnected)
          Row(
            children: [
              Expanded(
                child:
                    autoTrigger
                        ? _buildAutoTriggerControls(context)
                        : _buildManualTriggerControls(),
              ),
            ],
          ),
      ],
    );
  }

  // 构建自动触发控制区
  Widget _buildAutoTriggerControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('自动触发: $triggerInterval ms'),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _showIntervalDialog(context),
          tooltip: '设置触发间隔',
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onToggleAutoTrigger,
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
          onPressed: onToggleAutoTrigger,
          child: const Text('启动自动'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: isLoading ? null : onTriggerSample,
          child:
              isLoading
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
      text: triggerInterval.toString(),
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
              hintText: '输入200-10000之间的值',
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
                if (value != null && value >= 200 && value <= 10000) {
                  onSetTriggerInterval(value);
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
