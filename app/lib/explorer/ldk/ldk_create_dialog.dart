import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';

import '../sheet_menu.dart';
import '../dialogs/landmark_properties_dialog.dart';

/// «Файл»: новый файл меток. Пользователь вводит только имя (остальные
/// свойства — через «Ещё...»); формат всегда `.ldk`, выбора нет.
/// Результат — свойства или null («ОТМЕНА»).
class LdkCreateDialog extends StatefulWidget {
  const LdkCreateDialog({super.key});

  static const int maxNameLength = 200;

  static Future<LandmarkProperties?> show(BuildContext context) =>
      showDialog<LandmarkProperties>(
        context: context,
        builder: (_) => const LdkCreateDialog(),
      );

  /// Спрашивает имя и создаёт файл в [folder]; [at] — центр карты (файлу
  /// координата не нужна, но черновик её требует). Возвращает путь файла
  /// или null (отмена или ошибка — с сообщением).
  static Future<String?> createIn(
    BuildContext context,
    LandmarkServices services,
    String folder, {
    LandmarkLocation? at,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final props = await show(context);
    if (props == null) return null;
    try {
      final path = await services.creation.create(
        MarkerDraft(
          type: LandmarkType.ldkFile,
          name: props.name,
          comment: props.comment,
          description: props.description,
          longitude: at?.longitude ?? 0,
          latitude: at?.latitude ?? 0,
          targetFolder: folder,
        ),
      );
      await services.explorerController.refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Файл создан')));
      return path;
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось создать: $e')));
      return null;
    }
  }

  @override
  State<LdkCreateDialog> createState() => _LdkCreateDialogState();
}

class _LdkCreateDialogState extends State<LdkCreateDialog> {
  final TextEditingController _name = TextEditingController();
  String _comment = '';
  String _description = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    final props = await LandmarkPropertiesDialog.show(
      context,
      initial: LandmarkProperties(
        name: _name.text,
        comment: _comment,
        description: _description,
      ),
    );
    if (props == null || !mounted) return;
    setState(() {
      _name.text = props.name;
      _comment = props.comment;
      _description = props.description;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const underline = UnderlineInputBorder(
      borderSide: BorderSide(color: SheetMenuColors.accent, width: 1.5),
    );
    const button = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5);
    return Dialog(
      key: const Key('ldk_create_dialog'),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: width * 0.075,
        vertical: 24,
      ),
      child: SizedBox(
        width: width * 0.85,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Icon(
                      Icons.description_outlined,
                      size: 24,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Файл',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: SheetMenuColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Имя',
                style: TextStyle(
                  fontSize: 12,
                  color: SheetMenuColors.accent,
                  letterSpacing: 0.5,
                ),
              ),
              TextField(
                key: const Key('ldk_create_name'),
                controller: _name,
                autofocus: true,
                maxLength: LdkCreateDialog.maxNameLength,
                style: const TextStyle(
                  fontSize: 16,
                  color: SheetMenuColors.text,
                ),
                decoration: const InputDecoration(
                  enabledBorder: underline,
                  focusedBorder: underline,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              Material(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  key: const Key('ldk_create_more'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: _more,
                  child: const SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        'Ещё...',
                        style: TextStyle(
                          fontSize: 15,
                          color: SheetMenuColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('ldk_create_cancel'),
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: SheetMenuColors.accent,
                    ),
                    child: const Text('ОТМЕНА', style: button),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    key: const Key('ldk_create_ok'),
                    onPressed: () => Navigator.pop(
                      context,
                      LandmarkProperties(
                        name: _name.text.trim(),
                        comment: _comment,
                        description: _description,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: SheetMenuColors.accent,
                    ),
                    child: const Text('ОК', style: button),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
