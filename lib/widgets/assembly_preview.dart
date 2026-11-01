part of '../main.dart';

class PCAssemblyPreview extends StatefulWidget {
  const PCAssemblyPreview({super.key, required this.installedTypes});

  final Set<String> installedTypes;

  @override
  State<PCAssemblyPreview> createState() => _PCAssemblyPreviewState();
}

class _PCAssemblyPreviewState extends State<PCAssemblyPreview> {
  double rotation = 0;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MÔ HÌNH LẮP RÁP 3D',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kéo ngang để xoay • linh kiện sáng lên khi được thêm.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) => setState(() {
              rotation = (rotation + details.delta.dx * .012) % (2 * math.pi);
            }),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: widget.installedTypes.length / 8,
              ),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, progress, _) => CustomPaint(
                painter: _PcAssemblyPainter(
                  widget.installedTypes,
                  progress,
                  rotation,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${widget.installedTypes.length}/8 đã lắp',
            style: const TextStyle(color: mint, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _PcAssemblyPainter extends CustomPainter {
  const _PcAssemblyPainter(this.installedTypes, this.progress, this.rotation);

  final Set<String> installedTypes;
  final double progress;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 180);
    canvas.translate(150, 90);
    canvas.scale(math.cos(rotation).abs().clamp(.28, 1.0), 1);
    canvas.translate(-150, -90);
    final edge = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final caseFill = Paint()..color = panel2;
    final side = Path()
      ..moveTo(63, 32)
      ..lineTo(202, 32)
      ..lineTo(241, 54)
      ..lineTo(241, 151)
      ..lineTo(102, 151)
      ..lineTo(63, 130)
      ..close();
    canvas.drawPath(side, caseFill);
    canvas.drawPath(side, edge);
    final front = Path()
      ..moveTo(63, 32)
      ..lineTo(102, 54)
      ..lineTo(102, 151)
      ..lineTo(63, 130)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xff202b37));
    canvas.drawPath(front, edge);
    final board = Path()
      ..moveTo(111, 60)
      ..lineTo(195, 60)
      ..lineTo(224, 76)
      ..lineTo(140, 76)
      ..close();
    _part(canvas, board, 'MAINBOARD', const Color(0xff2b8e75));
    final cpu = Path()
      ..moveTo(129, 64)
      ..lineTo(149, 64)
      ..lineTo(158, 69)
      ..lineTo(138, 69)
      ..close();
    _part(canvas, cpu, 'CPU', const Color(0xffd6913d));
    final ram = Path()
      ..moveTo(163, 61)
      ..lineTo(168, 61)
      ..lineTo(178, 67)
      ..lineTo(173, 67)
      ..close();
    _part(canvas, ram, 'RAM', const Color(0xff7694cb));
    final gpu = Path()
      ..moveTo(127, 91)
      ..lineTo(207, 91)
      ..lineTo(222, 100)
      ..lineTo(142, 100)
      ..close();
    _part(canvas, gpu, 'GPU', const Color(0xff55a8e2));
    final storage = Path()
      ..moveTo(111, 111)
      ..lineTo(143, 111)
      ..lineTo(154, 117)
      ..lineTo(122, 117)
      ..close();
    _part(canvas, storage, 'SSD', const Color(0xffa77ce0));
    final psu = Path()
      ..moveTo(113, 130)
      ..lineTo(165, 130)
      ..lineTo(178, 137)
      ..lineTo(126, 137)
      ..close();
    _part(canvas, psu, 'PSU', const Color(0xffd4a943));
    final fan = Paint()
      ..color = installedTypes.contains('CASE') ? mint : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(const Offset(82, 77), 10, fan);
    canvas.drawCircle(const Offset(82, 107), 10, fan);
    final cooler = Paint()
      ..color = installedTypes.contains('TẢN NHIỆT') ? mint : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(const Offset(147, 57), 13, cooler);
    final label = TextPainter(
      text: TextSpan(
        text: '${(progress * 100).round()}%',
        style: const TextStyle(
          color: mint,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(250, 32));
    canvas.restore();
  }

  void _part(Canvas canvas, Path path, String type, Color color) {
    final installed = installedTypes.contains(type);
    final fill = installed
        ? Color.lerp(panel, color, .45 + .55 * progress.clamp(0.0, 1.0))!
        : panel.withValues(alpha: .85);
    canvas.drawPath(path, Paint()..color = fill);
    final outline = Paint()
      ..color = installed ? mint : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, outline);
  }

  @override
  bool shouldRepaint(covariant _PcAssemblyPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.rotation != rotation ||
      !setEquals(oldDelegate.installedTypes, installedTypes);
}
