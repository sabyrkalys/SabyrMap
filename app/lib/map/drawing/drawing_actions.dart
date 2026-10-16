import 'package:app/landmarks/composite/edit_mode/edit_commands.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/landmark_services_provider.dart';
import '../../icons/icon_library_scanner.dart';
import '../../waypoints/new_marker/marker_type.dart';
import '../../waypoints/new_marker/new_marker_sheet.dart';
import '../../waypoints/waypoint_create_action.dart';
import '../map_target.dart';

/// «Новая метка»: лист типов; путевая точка — диалог точки в прицеле,
/// маршрут и область — рисование на карте (панель покажет карта). Общий
/// вход для меню МЕТКИ и карточки прицела; [onDrawingStarted] — меню
/// закрывается, чтобы не загораживать карту.
Future<void> openNewMarker(
  BuildContext context,
  WidgetRef ref, {
  IconLibraryScanner? iconScanner,
  VoidCallback? onDrawingStarted,
}) async {
  final type = await showNewMarkerSheet(context);
  if (type == null || !context.mounted) return;
  switch (type.id) {
    case MarkerTypeIds.waypoint:
      await createWaypointAtCrosshair(context, ref, iconScanner: iconScanner);
    case MarkerTypeIds.route:
      startDrawing(ref, LandmarkType.route);
      onDrawingStarted?.call();
    case MarkerTypeIds.area:
      startDrawing(ref, LandmarkType.area);
      onDrawingStarted?.call();
    default:
      // The other types come in a later iteration.
      debugPrint('Selected: ${type.id}');
  }
}

/// Начинает рисование [type]; сохранится в папку новых меток.
void startDrawing(WidgetRef ref, LandmarkType type) {
  ref.read(crosshairMenuOpenProvider.notifier).close();
  ref.read(landmarkServicesProvider).editMode.startNew(type, folder: ref.read(markerGroupFoldersProvider).unsorted);
}

/// Имя по умолчанию для нового объекта: «Маршрут N», «Область N» — на
/// один больше наибольшего N среди [existingNames].
String nextDrawingName(LandmarkType type, Iterable<String> existingNames) {
  final base = switch (type) {
    LandmarkType.route => 'Маршрут',
    LandmarkType.area => 'Область',
    LandmarkType.track => 'Путь',
    LandmarkType.set => 'Набор точек',
    _ => 'Метка',
  };
  final pattern = RegExp('^${RegExp.escape(base)} (\\d+)\$');
  var highest = 0;
  for (final name in existingNames) {
    final n = int.tryParse(pattern.firstMatch(name.trim())?.group(1) ?? '');
    if (n != null && n > highest) highest = n;
  }
  return '$base ${highest + 1}';
}

/// «Готово»: спрашивает имя и сохраняет нарисованный объект новым файлом.
/// Возвращает путь файла; null — имя не подтвердили или запись не
/// удалась (тогда рисование остаётся открытым, о причине — сообщение).
Future<String?> finishDrawing(BuildContext context, LandmarkServices services) async {
  final editMode = services.editMode;
  final target = editMode.state.target;
  if (target == null || !editMode.canFinish) return null;
  final messenger = ScaffoldMessenger.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      initial: nextDrawingName(target.type, services.index.byType(target.type).map((i) => i.name)),
    ),
  );
  if (name == null) return null;
  editMode.execute(UpdateMetadataCommand(patch: MetadataPatch(set: {LandmarkMetadata.nameKey: name})));
  try {
    final path = await editMode.saveAndClose();
    messenger.showSnackBar(SnackBar(content: Text('«$name» сохранено')));
    return path;
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    return null;
  }
}

/// Крестик на панели: с точками — после подтверждения, без них — сразу.
Future<void> cancelDrawing(BuildContext context, LandmarkServices services) async {
  final editMode = services.editMode;
  if (editMode.pointCount > 0) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Закрыть без сохранения?'),
        content: const Text('Нарисованные точки пропадут.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Рисовать дальше')),
          TextButton(
            key: const Key('drawing_discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  editMode.close();
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    Navigator.of(context).pop(name.isEmpty ? widget.initial : name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Название'),
    content: TextField(
      key: const Key('drawing_name_field'),
      controller: _name,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
      // Тема растягивает FilledButton во всю ширину — здесь кнопки в ряд.
      FilledButton(
        key: const Key('drawing_name_ok'),
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
        onPressed: _submit,
        child: const Text('Сохранить'),
      ),
    ],
  );
}
