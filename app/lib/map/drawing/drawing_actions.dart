import 'package:app/landmarks/composite/edit_mode/edit_commands.dart';
import 'package:app/landmarks/composite/edit_mode/edit_mode_controller.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../app/landmark_services_provider.dart';
import '../../icons/icon_library_scanner.dart';
import '../../waypoints/new_marker/marker_type.dart';
import '../../waypoints/new_marker/new_marker_sheet.dart';
import '../../waypoints/waypoint_create_action.dart';
import '../../waypoints/waypoint_dialog/marker_group.dart';
import '../../waypoints/waypoint_dialog/waypoint_data.dart';
import '../../waypoints/waypoint_dialog/waypoint_dialog.dart';
import '../map_focus.dart';
import '../map_target.dart';
import 'shape_dialogs.dart';

/// «Новая метка»: лист типов; путевая точка — диалог точки в прицеле;
/// маршрут, путь, область, набор — рисование на карте (панель покажет
/// карта); круг и текст — диалог, объект встаёт в прицел. Общий вход для
/// меню МЕТКИ и карточки прицела; [onDrawingStarted] — меню закрывается,
/// чтобы не загораживать карту.
Future<void> openNewMarker(
  BuildContext context,
  WidgetRef ref, {
  IconLibraryScanner? iconScanner,
  VoidCallback? onDrawingStarted,
}) async {
  final type = await showNewMarkerSheet(context);
  if (type == null || !context.mounted) return;
  // Набор точек: сначала его свойства — диалог путевой точки без
  // координат, потом точки рисуются на карте.
  if (type.id == MarkerTypeIds.set) {
    final container = ProviderScope.containerOf(context, listen: false);
    final data = await showSetDialog(context, iconScanner: iconScanner);
    if (data == null) return;
    final services = container.read(landmarkServicesProvider);
    final folders = container.read(markerGroupFoldersProvider);
    container.read(crosshairMenuOpenProvider.notifier).close();
    services.editMode.startNew(
      LandmarkType.set,
      folder: folderFor(folders, data.groupId) ?? folders.unsorted,
      metadata: setMetadata(data, services.index.byType(LandmarkType.set).map((i) => i.name)),
    );
    onDrawingStarted?.call();
    return;
  }
  final drawn = switch (type.id) {
    MarkerTypeIds.route => LandmarkType.route,
    MarkerTypeIds.path => LandmarkType.track,
    MarkerTypeIds.area => LandmarkType.area,
    _ => null,
  };
  if (drawn != null) {
    startDrawing(ref, drawn);
    onDrawingStarted?.call();
    return;
  }
  // Круг и текст: диалог — от навигатора, а не от меню, которое сейчас
  // закроется; контейнер берётся до того, как ref меню пропадёт.
  final host = Navigator.of(context).context;
  final container = ProviderScope.containerOf(context, listen: false);
  switch (type.id) {
    case MarkerTypeIds.waypoint:
      await createWaypointAtCrosshair(context, ref, iconScanner: iconScanner);
    case MarkerTypeIds.circle:
      onDrawingStarted?.call();
      await createCircleAtCrosshair(host, container);
    case MarkerTypeIds.text:
      onDrawingStarted?.call();
      await createTextAtCrosshair(host, container);
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

/// Поиск в «Управлении метками»: точки рисуемого набора списком;
/// нажатие показывает точку на карте.
Future<void> showSetPointsSheet(BuildContext context, WidgetRef ref) async {
  final object = ref.read(landmarkServicesProvider).editMode.state.target?.object;
  if (object is! SetObject || object.waypoints.isEmpty) return;
  final focus = ref.read(mapFocusProvider.notifier);
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        key: const Key('set_points_sheet'),
        shrinkWrap: true,
        children: [
          for (final (i, w) in object.waypoints.indexed)
            ListTile(
              key: Key('set_point_$i'),
              leading: const Icon(Icons.location_on_sharp),
              title: Text(w.userMetadata.name ?? 'Точка ${i + 1}'),
              subtitle: Text('${w.location.latitude.toStringAsFixed(5)}, ${w.location.longitude.toStringAsFixed(5)}'),
              onTap: () {
                Navigator.of(context).pop();
                focus.focus(LatLng(w.location.latitude, w.location.longitude));
              },
            ),
        ],
      ),
    ),
  );
}

/// Метаданные набора из диалога «Набор точек»; пустое имя — следующий
/// «Набор точек N» среди [existingNames].
LandmarkMetadata setMetadata(WaypointData data, Iterable<String> existingNames) {
  String? text(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
  final name = text(data.name) ?? nextDrawingName(LandmarkType.set, existingNames);
  return LandmarkMetadata(
    entries: {
      LandmarkMetadata.nameKey: name,
      LandmarkMetadata.kindKey: data.type,
      LandmarkMetadata.colorKey: ?data.colorValue,
      LandmarkMetadata.userIconKey: ?data.iconId,
      LandmarkMetadata.iconKey: ?data.markerIconId,
      LandmarkMetadata.commentKey: ?text(data.comment),
      LandmarkMetadata.descriptionKey: ?text(data.note),
      LandmarkMetadata.websiteKey: ?text(data.website),
      LandmarkMetadata.keywordsKey: ?text(data.keywords),
    },
  );
}

/// Имя по умолчанию для нового объекта: «Маршрут N», «Область N» — на
/// один больше наибольшего N среди [existingNames].
String nextDrawingName(LandmarkType type, Iterable<String> existingNames) {
  final base = switch (type) {
    LandmarkType.route => 'Маршрут',
    LandmarkType.area => 'Область',
    LandmarkType.track => 'Путь',
    LandmarkType.set => 'Набор точек',
    LandmarkType.circle => 'Круг',
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

/// «Готово»: спрашивает имя и сохраняет нарисованный объект новым файлом;
/// у объекта с именем (набор точек — его дали в диалоге до рисования)
/// сохраняет сразу. Возвращает путь файла; null — имя не подтвердили или
/// запись не удалась (тогда рисование остаётся открытым, о причине —
/// сообщение).
Future<String?> finishDrawing(BuildContext context, LandmarkServices services) async {
  final editMode = services.editMode;
  final target = editMode.state.target;
  if (target == null || !editMode.canFinish) return null;
  final messenger = ScaffoldMessenger.of(context);
  final given = target.object.userMetadata.name;
  if (given != null && given.trim().isNotEmpty) return _save(editMode, messenger, given);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      initial: nextDrawingName(target.type, services.index.byType(target.type).map((i) => i.name)),
    ),
  );
  if (name == null) return null;
  editMode.execute(UpdateMetadataCommand(patch: MetadataPatch(set: {LandmarkMetadata.nameKey: name})));
  return _save(editMode, messenger, name);
}

Future<String?> _save(EditModeController editMode, ScaffoldMessengerState messenger, String name) async {
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
