import 'package:app/landmarks/drafts/marker_draft.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/validation/validation_result.dart';
import 'package:app/landmarks/validation/waypoint_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../app/landmark_services_provider.dart';
import '../map_crosshair.dart';
import 'drawing_actions.dart';

/// Объект, который карта показывает черновиком, пока открыт диалог (круг
/// нужного радиуса вокруг прицела); null — ничего.
class DrawingPreview extends Notifier<LandmarkObject?> {
  @override
  LandmarkObject? build() => null;

  void show(LandmarkObject? object) => state = object;
}

final drawingPreviewProvider = NotifierProvider<DrawingPreview, LandmarkObject?>(DrawingPreview.new);

/// Радиусы круга одним нажатием, м.
const List<int> circleRadiusPresets = [50, 100, 250, 500, 1000];

/// Размеры надписи: подпись → размер шрифта.
const Map<String, int> textSizePresets = {'Мелкий': 12, 'Средний': 16, 'Крупный': 24};

/// Метров в [text] (запятая — тоже разделитель); null — не положительное
/// число в пределах [WaypointValidator.maxRadiusMeters].
double? parseRadius(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0 || value > WaypointValidator.maxRadiusMeters) return null;
  return value;
}

/// «Круг»: имя и радиус, центр — в прицеле. Пока диалог открыт, круг
/// виден на карте ([drawingPreviewProvider]).
Future<void> createCircleAtCrosshair(BuildContext context, ProviderContainer container) async {
  final at = container.read(mapCrosshairProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (at == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final services = container.read(landmarkServicesProvider);
  final center = LandmarkLocation(latitude: at.latitude, longitude: at.longitude);
  final preview = container.read(drawingPreviewProvider.notifier);
  final result = await showDialog<({String name, double radius})>(
    context: context,
    // Карта под диалогом не затемняется: круг должен быть виден.
    barrierColor: Colors.transparent,
    builder: (context) => _CircleDialog(
      initialName: nextDrawingName(LandmarkType.circle, services.index.byType(LandmarkType.circle).map((i) => i.name)),
      onRadius: (radius) => preview.show(CircleObject(center: center, radiusMeters: radius)),
    ),
  );
  preview.show(null);
  if (result == null) return;
  await _create(
    container,
    messenger,
    MarkerDraft(
      type: LandmarkType.circle,
      latitude: at.latitude,
      longitude: at.longitude,
      name: result.name,
      radiusMeters: result.radius,
      targetFolder: container.read(markerGroupFoldersProvider).unsorted,
    ),
    result.name,
  );
}

/// «Текст»: надпись и её размер в прицеле. Имя метки — сама надпись.
Future<void> createTextAtCrosshair(BuildContext context, ProviderContainer container) async {
  final LatLng? at = container.read(mapCrosshairProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (at == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Карта ещё не готова')));
    return;
  }
  final result = await showDialog<({String text, int size})>(
    context: context,
    builder: (context) => const _TextDialog(),
  );
  if (result == null) return;
  await _create(
    container,
    messenger,
    MarkerDraft(
      type: LandmarkType.text,
      latitude: at.latitude,
      longitude: at.longitude,
      name: result.text,
      text: result.text,
      extraMetadata: {TextObject.textSizeKey: result.size},
      targetFolder: container.read(markerGroupFoldersProvider).unsorted,
    ),
    result.text,
  );
}

Future<void> _create(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  MarkerDraft draft,
  String name,
) async {
  try {
    await container.read(landmarkServicesProvider).creation.create(draft);
    messenger.showSnackBar(SnackBar(content: Text('«$name» сохранено')));
  } on ValidationException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: ${e.errors.join('; ')}')));
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
  }
}

/// Тема растягивает FilledButton во всю ширину — в диалогах кнопки в ряд.
final ButtonStyle _rowButton = FilledButton.styleFrom(minimumSize: const Size(64, 40));

class _CircleDialog extends StatefulWidget {
  const _CircleDialog({required this.initialName, required this.onRadius});

  final String initialName;
  final ValueChanged<double> onRadius;

  @override
  State<_CircleDialog> createState() => _CircleDialogState();
}

class _CircleDialogState extends State<_CircleDialog> {
  static const int _defaultRadius = 100;

  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  final TextEditingController _radius = TextEditingController(text: '$_defaultRadius');
  double? _value = _defaultRadius.toDouble();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRadius(_value!));
  }

  @override
  void dispose() {
    _name.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _setRadius(String text) {
    final value = parseRadius(text);
    setState(() => _value = value);
    if (value != null) widget.onRadius(value);
  }

  @override
  // Внизу экрана: прицел и круг вокруг него остаются видны.
  Widget build(BuildContext context) => AlertDialog(
    alignment: Alignment.bottomCenter,
    insetPadding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
    title: const Text('Круг'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('circle_name_field'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('circle_radius_field'),
          controller: _radius,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Радиус, м',
            errorText: _value == null ? 'Введите число больше нуля' : null,
          ),
          onChanged: _setRadius,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 6,
            children: [
              for (final r in circleRadiusPresets)
                ChoiceChip(
                  key: Key('circle_radius_$r'),
                  label: Text(r >= 1000 ? '${r ~/ 1000} км' : '$r м'),
                  selected: _value == r.toDouble(),
                  onSelected: (_) {
                    _radius.text = '$r';
                    _setRadius('$r');
                  },
                ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
      FilledButton(
        key: const Key('circle_ok'),
        style: _rowButton,
        onPressed: _value == null
            ? null
            : () {
                final name = _name.text.trim();
                Navigator.of(context).pop((name: name.isEmpty ? widget.initialName : name, radius: _value!));
              },
        child: const Text('Сохранить'),
      ),
    ],
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog();

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final TextEditingController _text = TextEditingController();
  int _size = textSizePresets['Средний']!;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().isNotEmpty;

  void _submit() {
    if (_valid) Navigator.of(context).pop((text: _text.text.trim(), size: _size));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Текст на карте'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('text_field'),
          controller: _text,
          autofocus: true,
          maxLength: WaypointValidator.maxTextLength,
          decoration: const InputDecoration(labelText: 'Надпись', counterText: ''),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final MapEntry(key: label, value: size) in textSizePresets.entries)
              ChoiceChip(
                key: Key('text_size_$size'),
                label: Text(label),
                selected: _size == size,
                onSelected: (_) => setState(() => _size = size),
              ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
      FilledButton(
        key: const Key('text_ok'),
        style: _rowButton,
        onPressed: _valid ? _submit : null,
        child: const Text('Сохранить'),
      ),
    ],
  );
}
