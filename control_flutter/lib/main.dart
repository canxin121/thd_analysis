import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'screens/test_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THD 分析器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ).useSystemChineseFont(Brightness.light),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // 页面列表
  final List<Widget> _pages = [
    const MyHomePage(title: 'THD 波形分析器'),
    const TestPage(title: '串口通信测试'),
  ];

  // 页面标题
  final List<String> _titles = ['THD 波形分析器', '串口通信测试'];

  // 页面图标
  final List<IconData> _icons = [
    Icons.analytics_outlined,
    Icons.settings_input_component_outlined,
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(_titles[_selectedIndex]),
      ),
      // 侧边抽屉导航
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'THD 分析器',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '选择功能',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            for (int i = 0; i < _titles.length; i++)
              ListTile(
                leading: Icon(_icons[i]),
                title: Text(_titles[i]),
                selected: _selectedIndex == i,
                onTap: () {
                  _onItemTapped(i);
                  Navigator.pop(context); // 关闭抽屉
                },
              ),
          ],
        ),
      ),
      // 主体内容
      body: _pages[_selectedIndex],
    );
  }
}
