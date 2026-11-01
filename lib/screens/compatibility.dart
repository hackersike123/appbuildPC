part of '../main.dart';

class _LiveCompatibilitySummary extends StatelessWidget {
  const _LiveCompatibilitySummary({
    required this.report,
    required this.onDetails,
  });
  final Map<String, dynamic> report;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final status = report['status']?.toString() ?? 'partial';
    final issues = (report['issues'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final recommendations = (report['recommendations'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final color = status == 'incompatible' || status == 'error'
        ? Colors.redAccent
        : status == 'warning'
        ? Colors.amber
        : mint;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == 'compatible'
                    ? Icons.check_circle
                    : Icons.warning_amber,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report['message']?.toString() ??
                      switch (status) {
                        'compatible' => 'Các thông số đã có đều tương thích.',
                        'incompatible' =>
                          'Phát hiện linh kiện không tương thích.',
                        'warning' => 'Cần xem cảnh báo của cấu hình.',
                        'error' => 'Kiểm tra chưa hoàn tất.',
                        _ =>
                          'Đã kiểm tra một phần; còn thiếu thông số catalog.',
                      },
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...issues
                .take(2)
                .map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '• ${issue['message']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
          ],
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Đề xuất: ${recommendations.take(2).map((item) => '${item['name']} — ${item['recommendationReason'] ?? 'phù hợp hơn'}').join('; ')}',
              style: const TextStyle(color: mint, fontSize: 11),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDetails,
              icon: const Icon(Icons.article_outlined, size: 17),
              label: const Text('Xem báo cáo đầy đủ'),
            ),
          ),
        ],
      ),
    );
  }
}

class CompatibilityScreen extends StatelessWidget {
  const CompatibilityScreen({super.key, this.report});
  final Map<String, dynamic>? report;

  String _criterionTitle(String code) =>
      const {
        'SOCKET': 'Socket CPU / mainboard',
        'RAM': 'Chuẩn bộ nhớ RAM',
        'PSU': 'Công suất bộ nguồn',
        'CASE_SIZE': 'Chiều dài card đồ họa',
        'COOLER_SOCKET': 'Socket tản nhiệt',
        'CASE_FORM': 'Kích thước mainboard / case',
      }[code] ??
      code;

  String _issueTitle(String code) => _criterionTitle(code);

  Future<void> _replace(BuildContext context, Map<String, dynamic> item) async {
    try {
      await ApiClient.instance.updateComponent(
        item['type'].toString(),
        item['id'].toString(),
      );
      if (context.mounted) {
        showDemoMessage(context, 'Đã thay thế bằng ${item['name']}.');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (context.mounted) {
        showDemoMessage(context, 'Không thể thay thế: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Báo cáo tương thích',
    subtitle: 'Phân tích tự động • vừa xong',
    back: true,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          ScoreCard(
            score: parseApiNumber(report?['score'])?.round(),
            verdict: report?['status']?.toString(),
            selectedCount: parseApiNumber(report?['selectedCount'])?.round(),
            checkedCount: report?['criteria'] is List
                ? (report!['criteria'] as List)
                      .where(
                        (item) => item is Map && item['status'] != 'unchecked',
                      )
                      .length
                : null,
          ),
          const SizedBox(height: 14),
          if (report?['powerAssessment'] is Map)
            PowerAssessmentCard(
              assessment: Map<String, dynamic>.from(
                report!['powerAssessment'] as Map,
              ),
            ),
          if (report?['powerAssessment'] is Map) const SizedBox(height: 12),
          if (report != null)
            InfoTile(
              icon: report!['status'] == 'incompatible'
                  ? Icons.error_outline
                  : report!['status'] == 'partial'
                  ? Icons.info_outline
                  : Icons.check_circle_outline,
              text: switch (report!['status']) {
                'incompatible' =>
                  'Không tương thích • ${report!['selectedCount'] ?? 0} linh kiện đã kiểm tra.',
                'warning' =>
                  'Có cảnh báo • ${report!['selectedCount'] ?? 0} linh kiện đã kiểm tra.',
                'partial' => 'Đã kiểm tra các cặp có đủ dữ liệu; tiêu chí còn lại thiếu thông số trong SQL.',
                _ => 'Tương thích trong phạm vi các thông số SQL hiện có.',
              },
            ),
          if (report != null) const SizedBox(height: 10),
          if (report == null)
            const WarningRow(
              icon: Icons.info_outline,
              color: Colors.amber,
              title: 'Chưa có báo cáo từ API',
              text: 'Đăng nhập và chọn linh kiện để kiểm tra cấu hình thật.',
            )
          else
            ...(report!['issues'] as List<dynamic>).map(
              (issue) => WarningRow(
                icon: issue['severity'] == 'error'
                    ? Icons.error_outline
                    : Icons.warning_amber,
                color: issue['severity'] == 'error'
                    ? Colors.redAccent
                    : Colors.amber,
                title: _issueTitle(issue['code'].toString()),
                text: issue['message'].toString(),
              ),
            ),
          if (report?['criteria'] is List)
            ...((report!['criteria'] as List).map(
              (criterion) => CompatibilityCriterionCard(
                title: _criterionTitle(criterion['code'].toString()),
                status: criterion['status']?.toString() ?? 'unchecked',
                detail: criterion['detail']?.toString() ?? '',
                remediation: criterion['remediation']?.toString() ?? '',
              ),
            )),
          const SizedBox(height: 14),
          const Text(
            'Đề xuất thay thế',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (report?['recommendations'] is List &&
              (report!['recommendations'] as List).isNotEmpty)
            ...(report!['recommendations'] as List).map((item) {
              final product = Map<String, dynamic>.from(item as Map);
              return CardBox(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${product['name']}\n${product['price']}đ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _replace(context, product),
                      child: const Text('Thay thế'),
                    ),
                  ],
                ),
              );
            })
          else
            const Text(
              'Chưa có linh kiện thay thế phù hợp từ catalog hiện tại.',
              style: TextStyle(color: muted),
            ),
        ],
      ),
    ),
  );
}
