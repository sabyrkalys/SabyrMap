import 'package:flutter/material.dart';

/// A row with an icon, the chosen option's label and a chevron; a tap opens
/// the options under it.
class DropdownField<T> extends StatelessWidget {
  const DropdownField({
    super.key,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  static const Color iconColor = Color(0xFF333333);
  static const Color textColor = Color(0xFF212121);
  static const Color chevronColor = Color(0xFF757575);

  final IconData icon;
  final T value;

  /// Value and label of each option, in order.
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      tooltip: '',
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [for (final (option, text) in options) PopupMenuItem(value: option, child: Text(text))],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 16, color: textColor)),
            ),
            const Icon(Icons.expand_more_sharp, size: 20, color: chevronColor),
          ],
        ),
      ),
    );
  }
}
