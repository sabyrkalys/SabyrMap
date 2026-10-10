import 'dart:math' as math;

import 'package:app/landmarks/composite/statistics/elevation_profile.dart';
import 'package:app/landmarks/models/landmark_location.dart';
import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// Превью формы объекта (маршрут, контур области) — без подложки карты.
///
/// Decision: настоящая карта в шапке — отдельная задача; здесь линия в
/// простой равнопромежуточной проекции, чтобы была видна форма.
class GeometryPreview extends StatelessWidget {
  const GeometryPreview({super.key, required this.points, required this.color, this.closed = false});

  final List<LandmarkLocation> points;
  final Color color;
  final bool closed;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('details_geometry_preview'),
    height: 140,
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
    child: points.length < 2
        ? const Center(child: Text('Мало точек для превью', style: TextStyle(color: SheetMenuColors.secondary)))
        : CustomPaint(painter: _GeometryPainter(points, color, closed)),
  );
}

class _GeometryPainter extends CustomPainter {
  _GeometryPainter(this.points, this.color, this.closed);

  final List<LandmarkLocation> points;
  final Color color;
  final bool closed;

  @override
  void paint(Canvas canvas, Size size) {
    final lat0 = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final k = math.cos(lat0 * math.pi / 180);
    final xs = [for (final p in points) p.longitude * k];
    final ys = [for (final p in points) p.latitude];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final span = math.max(maxX - minX, maxY - minY);
    const pad = 16.0;
    final scale = span == 0 ? 1.0 : math.min(size.width - 2 * pad, size.height - 2 * pad) / span;
    final dx = (size.width - (maxX - minX) * scale) / 2;
    final dy = (size.height - (maxY - minY) * scale) / 2;
    Offset at(int i) => Offset(dx + (xs[i] - minX) * scale, size.height - dy - (ys[i] - minY) * scale);
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    if (closed) {
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.2));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_GeometryPainter old) => old.points != points || old.color != color || old.closed != closed;
}

/// Профиль высоты трека; без высот — прямая линия и пояснение.
class ElevationProfilePreview extends StatelessWidget {
  const ElevationProfilePreview({super.key, required this.locations});

  final List<LandmarkLocation> locations;

  @override
  Widget build(BuildContext context) {
    final profile = ElevationProfileBuilder.build(locations);
    final points = profile.points;
    return Container(
      key: const Key('details_profile_preview'),
      height: 120,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ProfilePainter(points))),
          if (points.length < 2)
            const Center(child: Text('Нет данных о высоте', style: TextStyle(color: SheetMenuColors.secondary))),
        ],
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.points);

  final List<ElevationPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = SheetMenuColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const pad = 12.0;
    if (points.length < 2) {
      canvas.drawLine(Offset(pad, size.height - pad), Offset(size.width - pad, size.height - pad), stroke);
      return;
    }
    final maxD = points.last.distanceMeters == 0 ? 1.0 : points.last.distanceMeters;
    final minE = points.map((p) => p.elevationMeters).reduce(math.min);
    final maxE = points.map((p) => p.elevationMeters).reduce(math.max);
    final spanE = maxE - minE == 0 ? 1.0 : maxE - minE;
    Offset at(ElevationPoint p) => Offset(
      pad + p.distanceMeters / maxD * (size.width - 2 * pad),
      size.height - pad - (p.elevationMeters - minE) / spanE * (size.height - 2 * pad),
    );
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => old.points != points;
}
