import 'package:flutter/material.dart';

import '../../../explorer/sheet_menu.dart';
import '../../models/layer_look.dart';
import 'layer_look_sheet.dart';

/// «Изменить цвет»: яркость, контраст, насыщенность и оттенок слоя.
class LayerColorSheet extends LayerLookSheet {
  const LayerColorSheet({super.key, required super.sourceId});

  static Future<void> show(BuildContext context, String sourceId) =>
      LayerLookSheet.open(context, LayerColorSheet(sourceId: sourceId));

  /// Оттенки палитры (альфа — сила наложения).
  static const List<int> tints = [0x80D32F2F, 0x80F57C00, 0x80FBC02D, 0x80388E3C, 0x801976D2, 0x807B1FA2, 0x80795548];

  @override
  LayerLookSheetState<LayerColorSheet> createState() => _LayerColorSheetState();
}

class _LayerColorSheetState extends LayerLookSheetState<LayerColorSheet> {
  @override
  String get title => 'Цвет';

  @override
  LayerLook reset(LayerLook look) => look.copyWith(color: const LayerLook().color.copyWith(inverted: look.color.inverted));

  @override
  List<Widget> buildBody(BuildContext context, LayerLook look) {
    final color = look.color;
    return [
      LookSlider(
        key: const Key('color_brightness'),
        label: 'Яркость',
        value: color.brightness * 100,
        min: -100,
        max: 100,
        onChanged: (v) => apply(look.copyWith(color: color.copyWith(brightness: v.round() / 100))),
      ),
      LookSlider(
        key: const Key('color_contrast'),
        label: 'Контраст',
        value: color.contrast * 100,
        min: 0,
        max: 200,
        onChanged: (v) => apply(look.copyWith(color: color.copyWith(contrast: v.round() / 100))),
      ),
      LookSlider(
        key: const Key('color_saturation'),
        label: 'Насыщенность',
        value: color.saturation * 100,
        min: 0,
        max: 200,
        onChanged: (v) => apply(look.copyWith(color: color.copyWith(saturation: v.round() / 100))),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 8),
        child: Text('Оттенок', style: TextStyle(fontSize: 15, color: SheetMenuColors.text)),
      ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _TintSwatch(
            key: const Key('color_tint_none'),
            color: null,
            selected: color.tint == null,
            onTap: () => apply(look.copyWith(color: color.copyWith(tint: null))),
          ),
          for (final tint in LayerColorSheet.tints)
            _TintSwatch(
              key: Key('color_tint_$tint'),
              color: Color(tint | 0xFF000000),
              selected: color.tint == tint,
              onTap: () => apply(look.copyWith(color: color.copyWith(tint: tint))),
            ),
        ],
      ),
    ];
  }
}

class _TintSwatch extends StatelessWidget {
  const _TintSwatch({super.key, required this.color, required this.selected, required this.onTap});

  /// Null — без оттенка.
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color ?? Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? SheetMenuColors.text : SheetMenuColors.divider,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null ? const Icon(Icons.block, size: 18, color: SheetMenuColors.secondary) : null,
        ),
      );
}
