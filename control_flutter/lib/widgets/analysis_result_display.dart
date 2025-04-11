import 'package:flutter/material.dart';
import '../types/adc_data_analysis.dart';
import '../waveform_utils.dart';

class AnalysisResultDisplay extends StatefulWidget {
  final AdcDataAndAnalysisResult? analysisResult;
  final bool useInternalScroll;

  const AnalysisResultDisplay({
    super.key,
    required this.analysisResult,
    this.useInternalScroll = true,
  });

  @override
  State<AnalysisResultDisplay> createState() => _AnalysisResultDisplayState();
}

class _AnalysisResultDisplayState extends State<AnalysisResultDisplay> {
  static const int _rowsPerPage = 8;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.analysisResult == null) {
      return const Center(child: Text('暂无分析数据'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth > 100;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 基本信息卡片
            _buildInfoCards(isWideLayout),

            const SizedBox(height: 16),

            // 谐波分量标题
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '谐波分量',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  // 分页控制器
                  if (_getTotalPages() > 1) _buildPaginationControls(),
                ],
              ),
            ),

            // 谐波表格
            _buildHarmonicsTable(isWideLayout, constraints.maxWidth),
          ],
        );

        return widget.useInternalScroll
            ? SingleChildScrollView(child: content)
            : content;
      },
    );
  }

  Widget _buildInfoCards(bool isWideLayout) {
    final result = widget.analysisResult!.harmonicsAnalysis;

    // 创建信息项
    final infoItems = [
      _InfoItem(
        icon: Icons.analytics_outlined,
        title: 'THD',
        value: '${result.thd.toStringAsFixed(2)}%',
      ),
      _InfoItem(
        icon: Icons.waves,
        title: '波形',
        value: getWaveformTypeName(result.waveform),
      ),
      _InfoItem(
        icon: Icons.trending_up,
        title: '直流偏移',
        value: result.hasDcOffset ? '存在' : '无',
        valueColor: result.hasDcOffset ? Colors.orange : Colors.green,
      ),
    ];

    // 根据布局宽度决定排列方式
    if (isWideLayout) {
      // 水平排列
      return Row(
        children:
            infoItems
                .map((item) => Expanded(child: _buildInfoCard(item)))
                .toList(),
      );
    } else {
      // 垂直排列
      return Column(children: infoItems.map(_buildInfoCard).toList());
    }
  }

  Widget _buildInfoCard(_InfoItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(item.icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: item.valueColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHarmonicsTable(bool isWideLayout, double availableWidth) {
    final result = widget.analysisResult!.harmonicsAnalysis;
    final totalHarmonics = result.harmonicIndices.length;

    if (totalHarmonics == 0) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text('无谐波分量数据')),
      );
    }

    // 计算当前页的数据
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex =
        (startIndex + _rowsPerPage < totalHarmonics)
            ? startIndex + _rowsPerPage
            : totalHarmonics;

    // 获取当前页的数据
    final pageHarmonicIndices = result.harmonicIndices.sublist(
      startIndex,
      endIndex,
    );
    final pageNormalizedHarmonics = result.normalizedHarmonics.sublist(
      startIndex,
      endIndex,
    );

    // 根据宽度决定布局
    final columns = isWideLayout ? 2 : 1;
    final rowsPerColumn = (pageHarmonicIndices.length / columns).ceil();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child:
            columns == 1
                ? _buildSingleColumnTable(
                  pageHarmonicIndices,
                  pageNormalizedHarmonics,
                )
                : _buildMultiColumnTable(
                  pageHarmonicIndices,
                  pageNormalizedHarmonics,
                  columns,
                  rowsPerColumn,
                ),
      ),
    );
  }

  Widget _buildSingleColumnTable(List<int> indices, List<double> values) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2)},
        border: TableBorder(
          verticalInside: BorderSide(color: Colors.grey.shade300, width: 1),
          horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // 表头
          TableRow(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            children: [
              _buildTableHeaderCell('谐波序号'),
              _buildTableHeaderCell('相对幅度 (%)'),
            ],
          ),
          // 数据行
          ...List.generate(indices.length, (index) {
            return TableRow(
              decoration:
                  index % 2 == 0
                      ? null
                      : BoxDecoration(color: Colors.grey.shade50),
              children: [
                _buildTableCell('${indices[index]}'),
                _buildTableCell((values[index] * 100).toStringAsFixed(2)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Text(text, textAlign: TextAlign.center),
    );
  }

  Widget _buildMultiColumnTable(
    List<int> indices,
    List<double> values,
    int columns,
    int rowsPerColumn,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(columns, (columnIndex) {
        // 计算每列的起始和结束索引
        final startIdx = columnIndex * rowsPerColumn;
        final endIdx =
            (startIdx + rowsPerColumn < indices.length)
                ? startIdx + rowsPerColumn
                : indices.length;

        // 如果这一列没有数据，返回空容器
        if (startIdx >= indices.length) return Container();

        // 获取这一列的数据
        final columnIndices = indices.sublist(startIdx, endIdx);
        final columnValues = values.sublist(startIdx, endIdx);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: columnIndex > 0 ? 8.0 : 0),
            child: _buildSingleColumnTable(columnIndices, columnValues),
          ),
        );
      }),
    );
  }

  Widget _buildPaginationControls() {
    final totalPages = _getTotalPages();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed:
              _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        ),
        Text('${_currentPage + 1}/$totalPages'),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed:
              _currentPage < totalPages - 1
                  ? () => setState(() => _currentPage++)
                  : null,
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        ),
      ],
    );
  }

  int _getTotalPages() {
    if (widget.analysisResult == null) return 1;

    final harmonicCount =
        widget.analysisResult!.harmonicsAnalysis.harmonicIndices.length;
    return (harmonicCount / _rowsPerPage).ceil();
  }
}

class _InfoItem {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  _InfoItem({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });
}
