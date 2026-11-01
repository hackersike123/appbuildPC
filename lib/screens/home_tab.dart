part of '../main.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.onOpen,
    required this.onTabOpen,
    required this.onAreaChanged,
    this.areaId = 'hcm',
    this.areaName = 'TP. Hồ Chí Minh',
  });
  final void Function(Widget) onOpen;
  final void Function(int) onTabOpen;
  final String areaId;
  final String areaName;
  final void Function(String id, String name) onAreaChanged;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late String currentAreaId = widget.areaId;
  late String currentAreaName = widget.areaName;
  bool loadingMarket = true;
  List<Map<String, dynamic>> marketItems = const [];
  String? marketError;
  String? marketUpdatedAt;
  Map<String, dynamic>? activeBuild;
  bool loadingBuild = true;
  List<Map<String, dynamic>> notifications = const [];

  @override
  void initState() {
    super.initState();
    _loadMarket();
    _loadBuild();
    _loadNotifications();
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaId != widget.areaId ||
        oldWidget.areaName != widget.areaName) {
      currentAreaId = widget.areaId;
      currentAreaName = widget.areaName;
      loadingMarket = true;
      _loadMarket();
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final items = await ApiClient.instance.notifications();
      if (mounted) setState(() => notifications = items);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Thông báo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
            if (notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Text(
                  'Bạn chưa có thông báo mới.',
                  style: TextStyle(color: muted),
                ),
              )
            else
              ...notifications.map(
                (item) => ListTile(
                  leading: const Icon(Icons.notifications_none, color: mint),
                  title: Text(item['title'] as String? ?? 'Thông báo'),
                  subtitle: Text(item['message'] as String? ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
    if (notifications.any((item) => item['read'] == false)) {
      await ApiClient.instance.markNotificationsRead();
      if (mounted) {
        setState(() {
          notifications = notifications
              .map((item) => {...item, 'read': true})
              .toList();
        });
      }
    }
  }

  Future<void> _loadBuild() async {
    try {
      final builds = await ApiClient.instance.builds();
      if (!mounted) return;
      setState(() {
        activeBuild = builds.isEmpty ? null : builds.first;
        loadingBuild = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingBuild = false);
    }
  }

  Future<void> _changeArea() async {
    try {
      final areas = await ApiClient.instance.areas();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: panel,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Chọn khu vực định giá',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              ...areas.map(
                (item) => ListTile(
                  title: Text(item['name'] as String),
                  trailing: item['id'] == currentAreaId
                      ? const Icon(Icons.check, color: mint)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final result = await ApiClient.instance.resolveLocation(
        areaId: chosen['id'] as String,
      );
      final area = Map<String, dynamic>.from(result['area'] as Map);
      await ApiClient.instance.updateProfile(areaId: area['id'] as String);
      currentAreaId = area['id'] as String;
      currentAreaName = area['name'] as String;
      if (mounted) {
        setState(() {
          loadingMarket = true;
          marketError = null;
        });
      }
      widget.onAreaChanged(currentAreaId, currentAreaName);
      await _loadMarket();
    } catch (_) {
      if (mounted) {
        showDemoMessage(context, 'Không tải được danh sách khu vực.');
      }
    }
  }

  Future<void> _loadMarket() async {
    try {
      final result = await ApiClient.instance.marketSummary(currentAreaId);
      final items = (result['items'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        marketItems = items;
        marketUpdatedAt = result['updatedAt']?.toString();
        marketError = null;
        loadingMarket = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        marketError = 'Chưa tải được dữ liệu giá';
        loadingMarket = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào, ${ApiClient.instance.currentUser?['name'] ?? 'bạn'} 👋',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sẵn sàng lên cấu hình mới?',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              InkWell(
                onTap: _openNotifications,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: panel2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_none, size: 16),
                      if (notifications.any(
                        (item) => item['read'] == false,
                      )) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${notifications.where((item) => item['read'] == false).length}',
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _changeArea,
            child: InfoTile(
              icon: Icons.location_on_outlined,
              text: 'Giá theo khu vực · $currentAreaName',
              trailing: 'Thay đổi',
            ),
          ),
          const SizedBox(height: 16),
          InfoTile(
            icon: Icons.check_circle_outline,
            text:
                'Giá thị trường tại $currentAreaName\nNguồn: SQL • ${marketUpdatedAt == null ? 'đang tải thời điểm cập nhật' : 'cập nhật ${marketUpdatedAt!.replaceFirst('T', ' ').split('.').first}'}',
          ),
          const SizedBox(height: 16),
          MarketCard(
            items: marketItems,
            loading: loadingMarket,
            error: marketError,
            onTap: () => widget.onOpen(
              MarketChangesScreen(
                areaName: currentAreaName,
                items: marketItems,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lối vào nhanh',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Tối ưu một tay',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.65,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              QuickCard(
                icon: Icons.memory,
                text: 'Build PC',
                onTap: () => widget.onTabOpen(1),
              ),
              QuickCard(
                icon: Icons.camera_alt_outlined,
                text: 'Quét SP',
                onTap: () => widget.onOpen(
                  ScannerScreen(
                    onOpenBuild: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                      widget.onTabOpen(1);
                    },
                  ),
                ),
              ),
              QuickCard(
                icon: Icons.scatter_plot,
                text: 'So giá',
                onTap: () => widget.onOpen(const CompareProductsScreen()),
              ),
              QuickCard(
                icon: Icons.chat_bubble_outline,
                text: 'Tư vấn',
                onTap: () => widget.onOpen(
                  ChatTab(
                    onOpenBuild: () {
                      Navigator.of(context).pop();
                      widget.onTabOpen(1);
                    },
                  ),
                ),
              ),
              QuickCard(
                icon: Icons.category_outlined,
                text: 'Chọn linh kiện',
                onTap: () => widget.onTabOpen(1),
              ),
              QuickCard(
                icon: Icons.bookmark_border,
                text: 'Cấu hình đã lưu',
                onTap: () => widget.onTabOpen(2),
              ),
            ],
          ),
          const SizedBox(height: 18),
          BuildProgress(
            buildData: activeBuild,
            loading: loadingBuild,
            onContinue: activeBuild == null ? null : () => widget.onTabOpen(1),
          ),
        ],
      ),
    ),
  );
}
