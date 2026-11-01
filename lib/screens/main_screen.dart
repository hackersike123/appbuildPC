part of '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.areaId = 'hcm',
    this.areaName = 'TP. Hồ Chí Minh',
  });
  final String areaId;
  final String areaName;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _homeKey = GlobalKey<_HomeTabState>();
  final _buildKey = GlobalKey<_BuildTabState>();
  int tab = 0;
  int savedVersion = 0;
  late String areaId = widget.areaId;
  late String areaName = widget.areaName;
  @override
  Widget build(BuildContext context) => _keepAndroidAppInBackgroundOnRootBack(
    context,
    child: Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          HomeTab(
            key: _homeKey,
            onOpen: _open,
            onTabOpen: _switchTab,
            areaId: areaId,
            areaName: areaName,
            onAreaChanged: (id, name) => setState(() {
              areaId = id;
              areaName = name;
            }),
          ),
          BuildTab(key: _buildKey),
          SavedTab(key: ValueKey(savedVersion)),
          ChatTab(onOpenBuild: _openBuildTab),
          AccountTab(
            onAreaChanged: (id, name) => setState(() {
              areaId = id;
              areaName = name;
            }),
          ),
        ],
      ),
      bottomNavigationBar: SizedBox(
        height: 72,
        child: NavigationBar(
          backgroundColor: panel,
          indicatorColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: tab,
          onDestinationSelected: _switchTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.memory_outlined),
              selectedIcon: Icon(Icons.memory),
              label: 'Build',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: 'Đã lưu',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Tư vấn',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Tài khoản',
            ),
          ],
        ),
      ),
    ),
  );
  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _switchTab(int value) {
    setState(() {
      tab = value;
      if (value == 2) savedVersion++;
    });
    if (value == 0) _homeKey.currentState?._loadBuild();
    if (value == 1) _buildKey.currentState?._loadLatestBuild();
  }

  void _openBuildTab() => _switchTab(1);
}
