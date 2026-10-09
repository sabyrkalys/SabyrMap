import 'package:flutter/material.dart';

import 'explorer_style.dart';

/// Полоса занятого места: зелёная заливка на сером фоне.
class StorageMeter extends StatelessWidget {
  const StorageMeter({super.key, required this.usedBytes, required this.totalBytes, this.height = 8});

  final int usedBytes;
  final int totalBytes;
  final double height;

  /// Доля занятого, 0..1; без объёма — 0.
  static double fractionOf(int used, int total) => total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);

  double get fraction => fractionOf(usedBytes, totalBytes);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: height,
      child: LinearProgressIndicator(
        key: const Key('storage_meter_bar'),
        value: fraction,
        backgroundColor: ExplorerStyle.meterTrack,
        color: ExplorerStyle.meterFill,
      ),
    ),
  );
}
