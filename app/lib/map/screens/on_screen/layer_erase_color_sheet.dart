import 'package:flutter/material.dart';

import '../../../explorer/sheet_menu.dart';
import '../../../maps/color/color_range.dart';
import '../../../maps/color/erase_color_settings.dart';
import '../../models/layer_look.dart';
import 'layer_look_sheet.dart';

/// «Удалить цвет»: пиксели слоя около выбранного цвета (по каждому
/// каналу ± ширина диапазона) становятся прозрачными.
class LayerEraseColorSheet extends LayerLookSheet {
  const LayerEraseColorSheet({super.key, required super.sourceId});

  static Future<void> show(BuildContext context, String sourceId) =>
      LayerLookSheet.open(context, LayerEraseColorSheet(sourceId: sourceId));

  /// Белый: самый частый фон, который убирают с топокарт.
  static const int defaultColor = 0xFFFFFFFF;

  @override
  LayerLookSheetState<LayerEraseColorSheet> createState() => _LayerEraseColorSheetState();
}

class _LayerEraseColorSheetState extends LayerLookSheetState<LayerEraseColorSheet> {
  static const _channels = ['Красный (R)', 'Зелёный (G)', 'Синий (B)'];
  static const _channelColors = [Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2)];

  @override
  String get title => 'Удалить цвет';

  @override
  LayerLook reset(LayerLook look) => look.copyWith(erase: const EraseColorSettings());

  /// Диапазоны настройки, по одному на канал (пустые — белый, ширина по умолчанию).
  List<ColorRange> _ranges(EraseColorSettings erase) => erase.ranges.length == 3
      ? erase.ranges
      : EraseColorSettings.fromColor(LayerEraseColorSheet.defaultColor).ranges;

  EraseColorSettings _with(EraseColorSettings erase, List<ColorRange> ranges) {
    final argb = 0xFF000000 | ranges[0].center << 16 | ranges[1].center << 8 | ranges[2].center;
    return EraseColorSettings.fromColor(argb, width: ranges.first.width, enabled: erase.enabled);
  }

  @override
  List<Widget> buildBody(BuildContext context, LayerLook look) {
    final erase = look.erase;
    final ranges = _ranges(erase);
    final color = Color(0xFF000000 | ranges[0].center << 16 | ranges[1].center << 8 | ranges[2].center);
    return [
      SwitchListTile(
        key: const Key('erase_enabled'),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: SheetMenuColors.accent,
        title: const Text('Включить', style: TextStyle(fontSize: 16, color: SheetMenuColors.text)),
        secondary: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: SheetMenuColors.divider),
          ),
        ),
        value: erase.enabled,
        onChanged: (v) => apply(look.copyWith(erase: _with(erase, ranges).copyWith(enabled: v))),
      ),
      for (var c = 0; c < 3; c++)
        LookSlider(
          key: Key('erase_channel_$c'),
          label: _channels[c],
          color: _channelColors[c],
          value: ranges[c].center.toDouble(),
          min: 0,
          max: 255,
          onChanged: (v) {
            final next = List.of(ranges);
            next[c] = ColorRange(channel: c, center: v.round(), width: ranges[c].width);
            apply(look.copyWith(erase: _with(erase, next)));
          },
        ),
      LookSlider(
        key: const Key('erase_width'),
        label: 'Ширина диапазона',
        value: ranges.first.width.toDouble(),
        min: 1,
        max: 20,
        onChanged: (v) => apply(look.copyWith(erase: _with(erase, [
              for (final r in ranges) ColorRange(channel: r.channel, center: r.center, width: v.round()),
            ]))),
      ),
    ];
  }
}
