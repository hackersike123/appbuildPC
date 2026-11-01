// ignore_for_file: use_build_context_synchronously

part of '../main.dart';

class SavedTab extends StatefulWidget {
  const SavedTab({super.key});
  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  late Future<List<Map<String, dynamic>>> buildsFuture;

  @override
  void initState() {
    super.initState();
    buildsFuture = _loadBuilds();
  }

  Future<List<Map<String, dynamic>>> _loadBuilds() async {
    if (ApiClient.instance.token == null) {
      throw ApiException(
        'Phiên đăng nhập đã hết. Hãy đăng nhập lại để xem cấu hình đã lưu.',
      );
    }
    return ApiClient.instance.builds();
  }

  Future<void> _deleteBuild(Map<String, dynamic> build) async {
    final id = build['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình?'),
        content: Text(
          'Bạn có muốn xóa "${build['name'] ?? 'cấu hình'}" không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteBuild(id);
      if (mounted) {
        setState(() {
          buildsFuture = _loadBuilds();
        });
        showDemoMessage(context, 'Đã xóa cấu hình khỏi tài khoản.');
      }
    } on ApiException catch (error) {
      if (error.statusCode == 404 && mounted) {
        setState(() {
          buildsFuture = _loadBuilds();
        });
        showDemoMessage(context, 'Cấu hình này đã được xóa trước đó.');
      } else if (mounted) {
        showDemoMessage(context, 'Không thể xóa cấu hình: $error');
      }
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không thể xóa cấu hình: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Cấu hình đã lưu',
    subtitle: 'Cấu hình được đồng bộ với tài khoản',
    action: TextButton.icon(
      onPressed: () =>
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BuildTab(loadLatest: false),
            ),
          ).then((_) {
            if (mounted) {
              setState(() {
                buildsFuture = _loadBuilds();
              });
            }
          }),
      icon: const Icon(Icons.add, color: mint, size: 18),
      label: const Text('Tạo mới', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: buildsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: mint));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Không tải được cấu hình: ${snapshot.error}'),
            );
          }
          final builds = snapshot.data ?? const <Map<String, dynamic>>[];
          if (builds.isEmpty) {
            return const Center(
              child: Text('Bạn chưa có cấu hình nào được lưu.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            children: [
              InfoTile(
                icon: Icons.cloud_done_outlined,
                text:
                    'Đã lưu vào tài khoản ${ApiClient.instance.currentUser?['email'] ?? ''}',
              ),
              const SizedBox(height: 14),
              Tag('Tất cả ${builds.length}'),
              const SizedBox(height: 14),
              ...builds.map(
                (build) => SavedCard(
                  name: build['name']?.toString() ?? 'Cấu hình mới',
                  price: build['priceComplete'] == false
                      ? 'Chưa đủ giá SQL'
                      : '${build['priceEstimate'] == true ? '≈ ' : ''}${(parseApiNumber(build['totalPrice']) ?? 0).toStringAsFixed(0)}đ${build['priceEstimate'] == true ? ' • ước tính' : ''}',
                  status: build['priceComplete'] == false
                      ? 'THIẾU GIÁ'
                      : (parseApiNumber(build['completion']) ?? 0) == 100
                      ? 'TƯƠNG THÍCH'
                      : 'ĐANG LÀM',
                  area: build['areaId']?.toString() ?? 'TP. HỒ CHÍ MINH',
                  components: build['components'] is Map
                      ? Map<String, dynamic>.from(build['components'] as Map)
                      : const {},
                  onEdit: () =>
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BuildTab(initialBuild: build),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {
                            buildsFuture = _loadBuilds();
                          });
                        }
                      }),
                  onDelete: () => _deleteBuild(build),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class AccountTab extends StatefulWidget {
  const AccountTab({super.key, this.onAreaChanged});
  final void Function(String id, String name)? onAreaChanged;
  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  bool pricePreference = true;
  bool priceNotifications = true;
  Map<String, dynamic>? get user => ApiClient.instance.currentUser;

  @override
  void initState() {
    super.initState();
    final preferences = user?['preferences'];
    if (preferences is Map) {
      pricePreference = preferences['pricePreference'] as bool? ?? true;
      priceNotifications = preferences['priceNotifications'] as bool? ?? true;
    }
  }

  Future<void> _updatePreference({
    bool? pricePreference,
    bool? priceNotifications,
  }) async {
    try {
      await ApiClient.instance.updateProfile(
        pricePreference: pricePreference,
        priceNotifications: priceNotifications,
      );
      if (!mounted) return;
      setState(() {
        if (pricePreference != null) this.pricePreference = pricePreference;
        if (priceNotifications != null) {
          this.priceNotifications = priceNotifications;
        }
      });
    } catch (error) {
      if (mounted) showMessage(context, 'Không thể lưu tùy chọn: $error');
    }
  }

  Future<void> _editProfile() async {
    final name = TextEditingController(text: user?['name']?.toString() ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chỉnh sửa tài khoản'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Tên người dùng'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ApiClient.instance.updateProfile(name: name.text.trim());
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                if (dialogContext.mounted) {
                  showDemoMessage(dialogContext, '$error');
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    name.dispose();
    if (result == true && mounted) setState(() {});
  }

  Future<void> _changeArea() async {
    final areas = await ApiClient.instance.areas();
    if (!mounted) return;
    final area = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: areas
            .map(
              (item) => ListTile(
                title: Text(item['name'].toString()),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
            )
            .toList(),
      ),
    );
    if (area == null) return;
    await ApiClient.instance.updateProfile(areaId: area['id'].toString());
    widget.onAreaChanged?.call(
      area['id'].toString(),
      area['name']?.toString() ?? area['id'].toString(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openPrivacy() async {
    final areaId = user?['areaId']?.toString() ?? 'hcm';
    String areaName = areaId;
    try {
      final areas = await ApiClient.instance.areas();
      areaName = areas
          .firstWhere(
            (item) => item['id']?.toString() == areaId,
            orElse: () => {'name': areaId},
          )['name']
          .toString();
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quyền riêng tư & vị trí'),
        content: Text(
          'Vị trí định giá hiện tại: $areaName\n\n'
          '• Vị trí: chỉ dùng khi bạn yêu cầu xác định khu vực giá.\n'
          '• Camera: chỉ dùng khi bạn mở chức năng quét sản phẩm.\n'
          '• Ảnh/thư viện: chỉ đọc ảnh bạn chọn để phân tích.\n'
          '• Dữ liệu cấu hình: lưu theo tài khoản và không chia sẻ công khai.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _changeArea();
            },
            child: const Text('Đổi khu vực'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSupport() async {
    final message = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trợ giúp & hỗ trợ'),
        content: TextField(
          controller: message,
          minLines: 4,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: 'Mô tả vấn đề (10–2.000 ký tự)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final request = await ApiClient.instance.submitSupportRequest(
                  message: message.text.trim(),
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                  showMessage(
                    context,
                    'Đã tiếp nhận yêu cầu ${request['id']}.',
                  );
                }
              } catch (error) {
                if (dialogContext.mounted) showMessage(dialogContext, '$error');
              }
            },
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
    message.dispose();
    if (result == true && mounted) setState(() {});
  }

  String _areaName(String? id) =>
      const {
        'hcm': 'TP. Hồ Chí Minh',
        'hanoi': 'Hà Nội',
        'danang': 'Đà Nẵng',
      }[id] ??
      id ??
      'TP. Hồ Chí Minh';

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Tài khoản',
    subtitle: 'Quản lý hồ sơ và trải nghiệm mua sắm',
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          CardBox(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: greenPanel,
                  backgroundImage:
                      user?['avatarUrl']?.toString().isNotEmpty == true
                      ? NetworkImage(user!['avatarUrl'].toString())
                      : null,
                  child: user?['avatarUrl']?.toString().isNotEmpty == true
                      ? null
                      : Text(
                          (user?['name']?.toString() ?? 'U')
                              .trim()
                              .split(RegExp(r'\s+'))
                              .last
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: mint,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?['name']?.toString() ?? 'Người dùng',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        user?['email']?.toString() ?? '',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _editProfile,
                  child: const Text('Chỉnh sửa'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _changeArea,
            child: InfoTile(
              icon: Icons.location_on_outlined,
              text:
                  'ĐỊNH GIÁ HIỆN TẠI · KHU VỰC\n${_areaName(user?['areaId']?.toString())}',
              trailing: 'Thay đổi',
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.local_offer_outlined,
                  title: 'Ưu tiên giá linh kiện',
                  detail: 'Hiển thị hàng mới trước',
                  end: pricePreference ? 'Hàng mới' : 'Giá tốt',
                  toggle: true,
                  value: pricePreference,
                  onToggle: (value) =>
                      _updatePreference(pricePreference: value),
                ),
                SettingRow(
                  icon: Icons.notifications_none,
                  title: 'Thông báo biến động giá',
                  detail: 'Báo khi giá thay đổi từ 3%',
                  toggle: true,
                  value: priceNotifications,
                  onToggle: (value) =>
                      _updatePreference(priceNotifications: value),
                ),
                SettingRow(
                  icon: Icons.price_change_outlined,
                  title: 'Cảnh báo giá đã đặt',
                  detail: 'Thêm, sửa hoặc xóa cảnh báo trên SQL',
                  end: '›',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PriceAlertsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.cancel_outlined,
                  title: 'Bảo mật & đổi mật khẩu',
                  end: '›',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  ),
                ),
                SettingRow(
                  icon: Icons.lock_outline,
                  title: 'Quyền riêng tư & vị trí',
                  detail: 'Vị trí: Khi dùng ứng dụng',
                  end: '›',
                  onTap: _openPrivacy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.help_outline,
                  title: 'Trợ giúp & liên hệ',
                  end: '›',
                  onTap: _openSupport,
                ),
                SettingRow(
                  icon: Icons.help_outline,
                  title: 'PCBuild Local',
                  detail: 'Ứng dụng xây dựng cấu hình PC',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            text: 'Đăng xuất',
            onPressed: () {
              ApiClient.instance.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
    ),
  );
}
