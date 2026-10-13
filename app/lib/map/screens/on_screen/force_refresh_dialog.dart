import 'package:flutter/material.dart';

import '../../../dialogs/confirm_dialog.dart';

/// Подтверждение флага принудительного обновления слоя.
abstract final class ForceRefreshDialog {
  static Future<bool> show(BuildContext context) => showConfirmDialog(
        context,
        title: 'Принудительное обновление',
        message: 'Сохранить флаг принудительного обновления для этого слоя?\n'
            'Изменение действует только в текущей сессии.',
        confirmLabel: 'ДА',
      );
}
