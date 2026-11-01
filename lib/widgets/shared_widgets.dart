part of '../main.dart';

class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: stroke),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Logo(),
      const SizedBox(width: 9),
      const Text(
        'PCBUILD LOCAL',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ],
  );
}

class Logo extends StatelessWidget {
  const Logo({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.memory, color: bg, size: 20),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: greenPanel,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: mint,
        fontWeight: FontWeight.bold,
        fontSize: 10,
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        color: muted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.text, required this.onPressed});
  final String text;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: mint,
        foregroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
  });
  final String text;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: stroke),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

class InfoTile extends StatelessWidget {
  const InfoTile({super.key, this.icon, required this.text, this.trailing});
  final IconData? icon;
  final String text;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: greenPanel,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        if (icon != null) Icon(icon, color: mint),
        if (icon != null) const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
        ),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(color: mint, fontSize: 11)),
      ],
    ),
  );
}

class MarketCard extends StatelessWidget {
  const MarketCard({
    super.key,
    this.items = const [],
    this.loading = false,
    this.error,
    this.onTap,
  });
  final List<Map<String, dynamic>> items;
  final bool loading;
  final String? error;
  final VoidCallback? onTap;

  String _price(dynamic value) {
    final price = (num.tryParse(value.toString()) ?? 0) / 1000000;
    return '${price.toStringAsFixed(2).replaceAll('.', ',')}tr';
  }

  @override
  Widget build(BuildContext context) {
    final changedItems = items
        .where((item) => (parseApiNumber(item['trend']) ?? 0) != 0)
        .toList();
    return InkWell(
      onTap: changedItems.isEmpty ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nhịp giá thị trường',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Tag('HÔM NAY'),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                  color: mint,
                  backgroundColor: stroke,
                ),
              )
            else if (error != null)
              Text(error!, style: const TextStyle(color: muted))
            else if (changedItems.isEmpty)
              const Text(
                'Chưa có linh kiện thay đổi giá trong khu vực này.',
                style: TextStyle(color: muted),
              )
            else
              ...changedItems
                  .take(3)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['name'] as String? ?? 'Sản phẩm',
                              style: const TextStyle(color: muted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final trend = parseApiNumber(item['trend']) ?? 0;
                              return Text(
                                '${_price(item['price'])}  ${trend < 0 ? '↓' : '↑'} ${trend.abs()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
            if (!loading && error == null && changedItems.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onTap,
                  child: const Text('Xem giá thị trường'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class QuickCard extends StatelessWidget {
  const QuickCard({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: CardBox(
      child: Row(
        children: [
          Icon(icon, color: mint),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    ),
  );
}

class BuildProgress extends StatelessWidget {
  const BuildProgress({
    super.key,
    this.buildData,
    this.loading = false,
    this.onContinue,
  });
  final Map<String, dynamic>? buildData;
  final bool loading;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CẤU HÌNH ĐANG LÀM',
          style: TextStyle(color: Colors.amber, fontSize: 10),
        ),
        const SizedBox(height: 8),
        if (loading)
          const Text(
            'Đang tải cấu hình của bạn...',
            style: TextStyle(color: muted),
          )
        else if (buildData == null)
          const Text(
            'Bạn chưa có cấu hình nào',
            style: TextStyle(fontWeight: FontWeight.bold),
          )
        else ...[
          Text(
            '${buildData!['name'] ?? 'Build của tôi'} • ${buildData!['completion'] ?? 0}%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (parseApiNumber(buildData!['completion']) ?? 0) / 100,
            color: mint,
            backgroundColor: stroke,
          ),
          const SizedBox(height: 8),
          Text(
            'Tạm tính: ${_formatVnd(buildData!['totalPrice'])}',
            style: const TextStyle(color: mint, fontSize: 19),
          ),
          const SizedBox(height: 4),
          Text(
            '${_remainingPrice(buildData!)} • ${_missingComponents(buildData!)}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (onContinue != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                child: const Text('Tiếp tục build'),
              ),
            ),
        ],
      ],
    ),
  );

  String _formatVnd(dynamic value) {
    final amount = (parseApiNumber(value) ?? 0).toInt();
    return '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
  }

  String _remainingPrice(Map<String, dynamic> build) {
    final budget = (parseApiNumber(build['budget']) ?? 0).toInt();
    final total = (parseApiNumber(build['totalPrice']) ?? 0).toInt();
    return 'Còn ${_formatVnd((budget - total).clamp(0, budget))}';
  }

  String _missingComponents(Map<String, dynamic> build) {
    final components = build['components'];
    if (components is! Map) return 'chưa đủ dữ liệu';
    final missing = components.values.where((value) => value == null).length;
    return missing == 0 ? 'đủ linh kiện' : 'thiếu $missing linh kiện';
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    this.amber = false,
  });
  final String label;
  final String value;
  final double progress;
  final bool amber;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: const TextStyle(color: muted, fontSize: 10),
        );
        final valueText = Text(
          value,
          style: TextStyle(color: amber ? Colors.amber : mint, fontSize: 11),
        );
        final header = constraints.maxWidth < 380
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labelText,
                  Align(alignment: Alignment.centerRight, child: valueText),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [labelText, valueText],
              );
        return Column(
          children: [
            header,
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress,
              color: amber ? Colors.orange : mint,
              backgroundColor: stroke,
            ),
          ],
        );
      },
    ),
  );
}

class ComponentRow extends StatelessWidget {
  const ComponentRow({
    super.key,
    required this.type,
    required this.name,
    required this.price,
    this.onTap,
    this.onDelete,
  });
  final String type;
  final String name;
  final String price;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final empty = name.startsWith('Kéo') || name.startsWith('Chọn');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: empty ? stroke : const Color(0xff145344)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, color: muted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type, style: const TextStyle(color: mint, fontSize: 9)),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: empty ? muted : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!empty)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: onDelete,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            if (!empty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: mint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: panel,
        border: Border.all(color: stroke),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              product.image,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.detail,
                  style: const TextStyle(color: mint, fontSize: 9),
                ),
                Text(product.name, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  product.price,
                  style: TextStyle(
                    color: product.hasPrice && !product.priceEstimate
                        ? mint
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (!product.hasPrice)
            const Tag('Thiếu giá')
          else if (product.priceEstimate)
            const Tag('Ước tính')
          else if (!product.used)
            const Tag('Phù hợp'),
        ],
      ),
    ),
  );
}

class PowerAssessmentCard extends StatelessWidget {
  const PowerAssessmentCard({super.key, required this.assessment});

  final Map<String, dynamic> assessment;

  @override
  Widget build(BuildContext context) {
    final estimated = parseApiNumber(assessment['estimatedLoadW'])?.round();
    final recommended = parseApiNumber(assessment['recommendedPsuW'])?.round();
    final manufacturer = parseApiNumber(assessment['manufacturerMinimumW'])
        ?.round();
    final selected = parseApiNumber(assessment['selectedPsuW'])?.round();
    final margin = parseApiNumber(assessment['marginW'])?.round();
    final manufacturerMargin = parseApiNumber(
      assessment['marginVsManufacturerW'],
    )?.round();
    final loadMargin = parseApiNumber(assessment['marginFromLoadW'])?.round();
    final gpuNames = (assessment['manufacturerGpuNames'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    final sources = (assessment['manufacturerSources'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    final resultColor = selected == null
        ? Colors.amber
        : selected >= (recommended ?? 0)
        ? mint
        : Colors.orange;
    String marginText(int? value) => value == null
        ? 'Chưa đủ dữ liệu'
        : value >= 0
        ? 'Dư ${value}W'
        : 'Thiếu ${value.abs()}W';

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ĐÁNH GIÁ BỘ NGUỒN',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _powerLine(
            'Tải CPU/GPU ước tính',
            estimated == null ? 'Chưa đủ dữ liệu' : '~${estimated}W',
          ),
          _powerLine(
            'Mức PSU tối thiểu đề nghị',
            recommended == null ? 'Chưa xác định' : '≥ ${recommended}W',
          ),
          _powerLine(
            'Mức tối thiểu theo hãng GPU',
            manufacturer == null
                ? 'Chưa có trong SQL'
                : '$manufacturer W${gpuNames.isEmpty ? '' : ' • ${gpuNames.join(', ')}'}',
          ),
          _powerLine(
            'PSU đang chọn',
            selected == null
                ? 'Chưa chọn'
                : '${assessment['selectedPsuName'] ?? 'PSU'} • ${selected}W',
          ),
          _powerLine('Dư/thiếu so với mức đề nghị', marginText(margin)),
          if (manufacturer != null)
            _powerLine(
              'Dư/thiếu so với mức hãng',
              marginText(manufacturerMargin),
            ),
          _powerLine(
            'Chênh so với tải ước tính',
            '${marginText(loadMargin)} • không phải mức PSU đề nghị',
          ),
          const Divider(height: 18),
          Text(
            selected == null
                ? 'Chưa chọn bộ nguồn.'
                : selected >= (recommended ?? 0)
                ? 'Đạt mức PSU đề nghị của cấu hình.'
                : 'Chưa đạt mức PSU đề nghị của cấu hình.',
            style: TextStyle(color: resultColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            assessment['method']?.toString() ??
                'Ước tính từ dữ liệu linh kiện SQL.',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Nguồn dữ liệu hãng: ${sources.map((source) => Uri.tryParse(source)?.host ?? source).join(', ')}',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _powerLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class CompatibilityCriterionCard extends StatelessWidget {
  const CompatibilityCriterionCard({
    super.key,
    required this.title,
    required this.status,
    required this.detail,
    required this.remediation,
  });

  final String title;
  final String status;
  final String detail;
  final String remediation;

  @override
  Widget build(BuildContext context) {
    final color = status == 'pass'
        ? mint
        : status == 'unchecked'
        ? Colors.amber
        : Colors.redAccent;
    final label = status == 'pass'
        ? 'ĐẠT'
        : status == 'unchecked'
        ? 'CHƯA KIỂM TRA'
        : status == 'warning'
        ? 'CẢNH BÁO'
        : 'KHÔNG ĐẠT';
    return CardBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    border: Border.all(color: color.withValues(alpha: .5)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detail, style: const TextStyle(fontSize: 12)),
            ],
            if (status != 'pass' && remediation.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(remediation, style: TextStyle(color: color, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    this.score,
    this.verdict,
    this.selectedCount,
    this.checkedCount,
  });
  final int? score;
  final String? verdict;
  final int? selectedCount;
  final int? checkedCount;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Row(
      children: [
        const CircleAvatar(
          radius: 30,
          backgroundColor: Color(0xff342c17),
          child: Text(
            'B',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verdict == 'incompatible'
                    ? 'Có linh kiện không tương thích'
                    : verdict == 'warning'
                    ? 'Có cảnh báo cần xem'
                    : verdict == 'partial'
                    ? 'Đã kiểm tra một phần'
                    : score == null
                    ? 'Chưa đủ dữ liệu'
                    : 'Không thấy xung đột đã biết',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${selectedCount ?? 0}/8 linh kiện • ${checkedCount ?? 0} tiêu chí đã kiểm tra${score == null ? '' : ' • $score/100 trên tiêu chí đã kiểm tra'}',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        Tag(score == null ? '—' : '$score/100'),
      ],
    ),
  );
}

class WarningRow extends StatelessWidget {
  const WarningRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: color.withValues(alpha: .55)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(text, style: const TextStyle(color: muted, fontSize: 10)),
            ],
          ),
        ),
      ],
    ),
  );
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text, required this.dark});
  final String text;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: dark ? panel : greenPanel,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(text, style: const TextStyle(fontSize: 12))],
    ),
  );
}

class SavedCard extends StatelessWidget {
  const SavedCard({
    super.key,
    required this.name,
    required this.price,
    required this.status,
    required this.area,
    required this.components,
    this.onEdit,
    this.onDelete,
  });
  final String name;
  final String price;
  final String status;
  final String area;
  final Map<String, dynamic> components;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
            Tag(status),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _componentSummary,
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Text(
          'GIÁ TẠI $area',
          style: const TextStyle(color: muted, fontSize: 9),
        ),
        Text(price, style: const TextStyle(color: mint, fontSize: 19)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Sửa'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Xóa'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  String get _componentSummary {
    final names = components.values
        .whereType<Map>()
        .map((item) => item['name']?.toString())
        .whereType<String>()
        .toList();
    return names.isEmpty ? 'Chưa chọn linh kiện' : names.join(' · ');
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.end,
    this.toggle = false,
    this.value = false,
    this.onTap,
    this.onToggle,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final String? end;
  final bool toggle;
  final bool value;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: panel2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: mint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
              ],
            ),
          ),
          if (toggle)
            Switch(value: value, onChanged: onToggle, activeThumbColor: mint)
          else
            Text(
              end ?? '›',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
        ],
      ),
    ),
  );
}
