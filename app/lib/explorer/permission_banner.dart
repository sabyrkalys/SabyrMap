import 'package:flutter/material.dart';

import 'explorer_style.dart';

/// Предупреждение «нет права доступа к файлам» с кнопкой «АКТИВИРОВАТЬ».
class PermissionBanner extends StatelessWidget {
  const PermissionBanner({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('permission_banner'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      children: [
        const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: ExplorerStyle.warning),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Вы не предоставили приложению право доступа к файлам.',
                style: TextStyle(fontSize: 14, color: ExplorerStyle.warning),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton(
            key: const Key('permission_activate'),
            onPressed: onActivate,
            style: OutlinedButton.styleFrom(foregroundColor: ExplorerStyle.warning),
            child: const Text('АКТИВИРОВАТЬ'),
          ),
        ),
      ],
    ),
  );
}
