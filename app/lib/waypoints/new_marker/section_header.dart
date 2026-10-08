import 'package:flutter/material.dart';

/// «— ЛОКАЛЬНЫЕ МЕТКИ»: a short line, then the section's name in capitals.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label});

  static const Color lineColor = Color(0xFFBDBDBD);
  static const Color textColor = Color(0xFF757575);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 24, child: Divider(height: 1, thickness: 1, color: lineColor)),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, color: textColor, letterSpacing: 0.5)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
        ],
      ),
    );
  }
}
