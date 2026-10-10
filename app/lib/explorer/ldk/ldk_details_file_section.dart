import 'package:flutter/material.dart';

import '../sheet_menu.dart';

/// Секция «ФАЙЛ»: Имя, Папка, Размер, Дата; сворачивается по стрелке.
class LdkDetailsFileSection extends StatelessWidget {
  const LdkDetailsFileSection({
    super.key,
    required this.name,
    required this.folder,
    required this.sizeBytes,
    required this.modified,
    required this.expanded,
    required this.onToggle,
    required this.onMore,
  });

  final String name;
  final String folder;
  final int? sizeBytes;
  final DateTime? modified;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onMore;

  /// «512 Б», «1,49 кБ», «2,30 МБ».
  static String formatSize(int bytes) {
    String two(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${two(bytes / 1024)} кБ';
    if (bytes < 1024 * 1024 * 1024) return '${two(bytes / 1024 / 1024)} МБ';
    return '${two(bytes / 1024 / 1024 / 1024)} ГБ';
  }

  /// `dd.MM.yyyy HH:mm:ss`, местное время.
  static String formatDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeBytes;
    final date = modified;
    final rows = [
      ('Имя', name),
      ('Папка', folder),
      ('Размер', size == null ? '—' : formatSize(size)),
      ('Дата', date == null ? '—' : formatDate(date)),
    ];
    return Column(
      key: const Key('ldk_file_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('ldk_file_toggle'),
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: onToggle,
            ),
            const Text(
              'ФАЙЛ',
              style: TextStyle(
                fontSize: 13,
                color: SheetMenuColors.secondary,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('ldk_file_more'),
              icon: const Icon(Icons.more_vert),
              onPressed: onMore,
            ),
          ],
        ),
        if (expanded)
          for (final (label, value) in rows)
            Padding(
              key: Key('ldk_file_row_$label'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: SheetMenuColors.secondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: SheetMenuColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
