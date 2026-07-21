import 'package:flutter/material.dart';

import '../models/file_entry.dart';

/// XP-flavoured painted icons: manila folder with gradient, typed documents.
class FileIconWidget extends StatelessWidget {
  final String name;
  final bool isDir;
  final double size;
  const FileIconWidget({
    super.key,
    required this.name,
    required this.isDir,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _IconPainter(kindOf(name, isDir)),
    );
  }
}

class _IconPainter extends CustomPainter {
  final FileKind kind;
  _IconPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 16, size.height / 16);
    if (kind == FileKind.folder) {
      _folder(canvas);
    } else {
      _document(canvas);
    }
    canvas.restore();
  }

  void _folder(Canvas c) {
    final outline = Paint()
      ..color = const Color(0xFF8B6914)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    // back flap
    final back = Path()
      ..moveTo(1, 4.5)
      ..lineTo(6, 4.5)
      ..lineTo(7.5, 6)
      ..lineTo(15, 6)
      ..lineTo(15, 13.5)
      ..lineTo(1, 13.5)
      ..close();
    c.drawPath(
      back,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE9A2), Color(0xFFF6C13C)],
        ).createShader(const Rect.fromLTWH(0, 3, 16, 12)),
    );
    c.drawPath(back, outline);
    // front face slightly lighter
    final front = Path()
      ..moveTo(1, 6.5)
      ..lineTo(15, 6.5)
      ..lineTo(14, 13.5)
      ..lineTo(1, 13.5)
      ..close();
    c.drawPath(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3C2), Color(0xFFFACC55)],
        ).createShader(const Rect.fromLTWH(0, 6, 16, 8)),
    );
    c.drawPath(front, outline);
  }

  void _document(Canvas c) {
    final (Color base, Color accent, String glyph) = switch (kind) {
      FileKind.image => (const Color(0xFFE7F0FA), const Color(0xFF3E7BC6), ''),
      FileKind.audio => (const Color(0xFFF3EDFA), const Color(0xFF7B52AB), ''),
      FileKind.video => (const Color(0xFFFAEDED), const Color(0xFFB0413E), ''),
      FileKind.document => (
        const Color(0xFFF6F6F0),
        const Color(0xFF3B6EA5),
        '',
      ),
      FileKind.code => (const Color(0xFFEDF7EE), const Color(0xFF2E7D32), ''),
      FileKind.archive => (
        const Color(0xFFFCF3E3),
        const Color(0xFFB8860B),
        '',
      ),
      FileKind.exe => (const Color(0xFFEEF2F8), const Color(0xFF44578A), ''),
      _ => (const Color(0xFFFDFDFD), const Color(0xFF8A8A8A), ''),
    };

    // page with folded corner
    final page = Path()
      ..moveTo(3, 1)
      ..lineTo(10.5, 1)
      ..lineTo(13.5, 4)
      ..lineTo(13.5, 15)
      ..lineTo(3, 15)
      ..close();
    c.drawPath(page, Paint()..color = base);
    c.drawPath(
      page,
      Paint()
        ..color = const Color(0xFF7A7A7A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    final fold = Path()
      ..moveTo(10.5, 1)
      ..lineTo(10.5, 4)
      ..lineTo(13.5, 4)
      ..close();
    c.drawPath(fold, Paint()..color = accent.withValues(alpha: 0.35));
    c.drawPath(
      fold,
      Paint()
        ..color = const Color(0xFF7A7A7A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    switch (kind) {
      case FileKind.image:
        // tiny landscape
        c.drawRect(
          const Rect.fromLTWH(4.5, 6, 7.5, 6),
          Paint()..color = const Color(0xFFBBD6F0),
        );
        final mountain = Path()
          ..moveTo(4.5, 12)
          ..lineTo(7.5, 8)
          ..lineTo(9.5, 10.5)
          ..lineTo(11, 9)
          ..lineTo(12, 12)
          ..close();
        c.drawPath(mountain, Paint()..color = accent);
        c.drawCircle(
          const Offset(10.7, 7.3),
          0.9,
          Paint()..color = const Color(0xFFF6C13C),
        );
      case FileKind.audio:
        final notePaint = Paint()..color = accent;
        c.drawCircle(const Offset(6, 11.5), 1.5, notePaint);
        c.drawCircle(const Offset(10.5, 10.5), 1.5, notePaint);
        c.drawRect(const Rect.fromLTWH(7, 5.5, 1, 6), notePaint);
        c.drawRect(const Rect.fromLTWH(11.5, 4.5, 1, 6), notePaint);
        c.drawRect(const Rect.fromLTWH(7, 4.5, 5.5, 1.4), notePaint);
      case FileKind.video:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4.5, 6.5, 8, 5.5),
            const Radius.circular(1),
          ),
          Paint()..color = accent,
        );
        final play = Path()
          ..moveTo(7.2, 7.8)
          ..lineTo(10.4, 9.25)
          ..lineTo(7.2, 10.7)
          ..close();
        c.drawPath(play, Paint()..color = Colors.white);
      case FileKind.code:
        final tp = Paint()
          ..color = accent
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        c.drawLine(const Offset(6.5, 7), const Offset(4.8, 9.2), tp);
        c.drawLine(const Offset(4.8, 9.2), const Offset(6.5, 11.4), tp);
        c.drawLine(const Offset(10, 7), const Offset(11.7, 9.2), tp);
        c.drawLine(const Offset(11.7, 9.2), const Offset(10, 11.4), tp);
      case FileKind.archive:
        c.drawRect(
          const Rect.fromLTWH(7.5, 2, 1.6, 10),
          Paint()..color = accent,
        );
        for (var y = 3.0; y < 11; y += 2) {
          c.drawRect(
            Rect.fromLTWH(7.5, y, 1.6, 0.8),
            Paint()..color = const Color(0xFFFCF3E3),
          );
        }
      case FileKind.exe:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4.5, 5.5, 7.5, 6),
            const Radius.circular(1),
          ),
          Paint()..color = accent,
        );
        c.drawRect(
          const Rect.fromLTWH(5.5, 6.5, 2.4, 1.8),
          Paint()..color = Colors.white70,
        );
      default:
        // text lines
        final lp = Paint()..color = accent.withValues(alpha: 0.75);
        for (var y = 6.0; y <= 12; y += 2) {
          c.drawRect(Rect.fromLTWH(4.5, y, y == 12 ? 5 : 8, 0.9), lp);
        }
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.kind != kind;
}
