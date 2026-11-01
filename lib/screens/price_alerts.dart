part of '../main.dart';

class PriceAlertsScreen extends StatefulWidget {
  const PriceAlertsScreen({super.key});

  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  late Future<List<Map<String, dynamic>>> alerts;

  @override
  void initState() {
    super.initState();
    alerts = ApiClient.instance.priceAlerts();
  }

  void _reload() => setState(() => alerts = ApiClient.instance.priceAlerts());

  Future<void> _edit(Map<String, dynamic> alert) async {
    final controller = TextEditingController(
      text: alert['targetPrice'].toString(),
    );
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sửa mức cảnh báo'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Giá mục tiêu (VNĐ)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')),
            ),
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (target == null || target <= 0) return;
    try {
      await ApiClient.instance.updatePriceAlert(
        id: alert['id'].toString(),
        productId: alert['productId'].toString(),
        targetPrice: target,
        areaId: alert['areaId'].toString(),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không sửa được cảnh báo: $error');
    }
  }

  Future<void> _delete(Map<String, dynamic> alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa cảnh báo giá?'),
        content: Text(
          'Xóa cảnh báo cho ${alert['productName'] ?? 'linh kiện này'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deletePriceAlert(alert['id'].toString());
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không xóa được cảnh báo: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Cảnh báo giá',
    subtitle: 'Các mức giá được lưu trong SQL',
    back: true,
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: alerts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: mint));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Không tải được cảnh báo: ${snapshot.error}'),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(child: Text('Chưa có cảnh báo giá nào.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: items
              .map(
                (item) => CardBox(
                  child: ListTile(
                    title: Text(
                      item['productName']?.toString() ??
                          item['productId'].toString(),
                    ),
                    subtitle: Text(
                      'Báo khi ≤ ${formatVnd(item['targetPrice'])} • ${item['areaId']} • hiện tại ${formatVnd(item['currentPrice'])}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) =>
                          action == 'edit' ? _edit(item) : _delete(item),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xóa')),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (next.text.length < 8 || next.text != confirmation.text) {
      showMessage(
        context,
        'Mật khẩu mới phải có ít nhất 8 ký tự và khớp xác nhận.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await ApiClient.instance.changePassword(current.text, next.text);
      if (!mounted) return;
      showMessage(context, 'Đã đổi mật khẩu thành công.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, 'Không thể đổi mật khẩu: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Đổi mật khẩu',
    subtitle: 'Bảo vệ tài khoản của bạn',
    back: true,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      children: [
        TextField(
          controller: current,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: next,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirmation,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          text: busy ? 'ĐANG CẬP NHẬT...' : 'ĐỔI MẬT KHẨU',
          onPressed: busy ? () {} : _submit,
        ),
      ],
    ),
  );
}
