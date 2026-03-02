import 'package:flutter/material.dart';

class MapPreview extends StatelessWidget {
  const MapPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E9F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Network Snapshot',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.map_rounded, size: 18),
                label: const Text('Open Map'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEFF4FF), Color(0xFFEAFCEF)],
              ),
              border: Border.all(color: const Color(0xFFDCE5F6)),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _NetworkPainter())),
                _StationTag(
                  label: 'KL Sentral',
                  color: const Color(0xFF0A57D5),
                  alignment: const Alignment(-0.55, -0.55),
                ),
                _StationTag(
                  label: 'KLCC',
                  color: const Color(0xFF00A86B),
                  alignment: const Alignment(0.55, -0.1),
                ),
                _StationTag(
                  label: 'Bukit Bintang',
                  color: const Color(0xFFFF9800),
                  alignment: const Alignment(0.2, 0.55),
                ),
                Align(
                  alignment: const Alignment(-0.08, -0.02),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0A3A8B),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Current best corridor: Kelana Jaya -> MRT Kajang',
            style: TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StationTag extends StatelessWidget {
  final String label;
  final Color color;
  final Alignment alignment;

  const _StationTag({
    required this.label,
    required this.color,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E9F6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.white
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final line = Paint()
      ..color = const Color(0xFF0A3A8B).withValues(alpha: 0.55)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width * 0.17, size.height * 0.28);
    path.cubicTo(
      size.width * 0.35,
      size.height * 0.12,
      size.width * 0.62,
      size.height * 0.16,
      size.width * 0.78,
      size.height * 0.40,
    );
    path.cubicTo(
      size.width * 0.62,
      size.height * 0.58,
      size.width * 0.40,
      size.height * 0.66,
      size.width * 0.32,
      size.height * 0.82,
    );

    canvas.drawPath(path, shadow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
