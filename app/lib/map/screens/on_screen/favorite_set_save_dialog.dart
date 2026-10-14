import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../explorer/sheet_menu.dart';
import '../../services/layer_manager.dart';
import '../../state/map_layers_controller.dart';

/// Диалог имени набора: «Сохранить в избранное» и «Переименовать».
class FavoriteSetNameDialog extends StatefulWidget {
  const FavoriteSetNameDialog({super.key, required this.title, this.initialName = ''});

  final String title;
  final String initialName;

  /// Введённое имя без пробелов по краям; null — отмена.
  static Future<String?> ask(BuildContext context, {required String title, String initialName = ''}) =>
      showDialog<String>(
        context: context,
        builder: (_) => FavoriteSetNameDialog(title: title, initialName: initialName),
      );

  @override
  State<FavoriteSetNameDialog> createState() => _FavoriteSetNameDialogState();
}

class _FavoriteSetNameDialogState extends State<FavoriteSetNameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('favorite_set_name'),
          controller: _name,
          autofocus: true,
          cursorColor: SheetMenuColors.accent,
          decoration: const InputDecoration(
            labelText: 'Имя',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: SheetMenuColors.accent, width: 2)),
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ОТМЕНА'),
          ),
          TextButton(
            key: const Key('favorite_set_ok'),
            style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
            onPressed: _submit,
            child: const Text('ОК'),
          ),
        ],
      );
}

/// «Сохранить в избранное»: текущая базовая карта, слои и их вид.
abstract final class FavoriteSetSaveDialog {
  static Future<void> show(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final name = await FavoriteSetNameDialog.ask(context, title: 'Сохранить в избранные');
    if (name == null) return;
    try {
      await container.read(mapLayersProvider.notifier).savePreset(name);
      messenger.showSnackBar(const SnackBar(content: Text('Набор сохранён')));
    } on LayerException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
