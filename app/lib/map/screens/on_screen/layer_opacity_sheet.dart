import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/catalog_repository.dart';
import '../../state/map_layers_controller.dart';
import '../layers_panel.dart';

const Color _accent = Color(0xFF00A38E);
const Color _ink = Color(0xFF333333);
const Color _secondary = Color(0xFF757575);

/// Непрозрачность одного слоя: слайдер 0–100 %, карта меняется сразу,
/// итог сохраняется, когда палец отпущен.
class LayerOpacitySheet extends ConsumerStatefulWidget {
  const LayerOpacitySheet({super.key, required this.sourceId});

  final String sourceId;

  static Future<void> show(BuildContext context, String sourceId) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: onScreenPanelBackground,
    barrierColor: Colors.transparent,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => LayerOpacitySheet(sourceId: sourceId),
  );

  @override
  ConsumerState<LayerOpacitySheet> createState() => _LayerOpacitySheetState();
}

class _LayerOpacitySheetState extends ConsumerState<LayerOpacitySheet> {
  /// Значение, пока палец на слайдере.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapLayersProvider);
    final id = widget.sourceId;
    final opacity = switch (id) {
      MapStateNotifier.orthophotosKey => state.orthophotoOpacity,
      MapStateNotifier.worldKey => state.worldOpacity,
      _ => state.overlays.where((l) => l.sourceId == id).firstOrNull?.opacity,
    };
    final name = layerName(ref.watch(catalogProvider).value ?? const [], widget.sourceId);
    final notifier = ref.read(mapLayersProvider.notifier);
    Future<void> preview(double v) => switch (id) {
      MapStateNotifier.orthophotosKey => notifier.previewOrthophotoOpacity(v),
      MapStateNotifier.worldKey => notifier.previewWorldOpacity(v),
      _ => notifier.previewOpacity(id, v),
    };
    Future<void> store(double v) => switch (id) {
      MapStateNotifier.orthophotosKey => notifier.setOrthophotoOpacity(v),
      MapStateNotifier.worldKey => notifier.setWorldOpacity(v),
      _ => notifier.setOpacity(id, v),
    };
    final value = (_dragging ?? opacity ?? 1.0) * 100;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_outlined, size: 24, color: _ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Непрозрачность · $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                  ),
                ),
                const Icon(Icons.opacity, size: 22, color: _ink),
                IconButton(
                  key: const Key('opacity_done'),
                  icon: const Icon(Icons.check, size: 22, color: _accent),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('0 %', style: TextStyle(fontSize: 13, color: _secondary)),
                const Spacer(),
                Text(
                  '${value.round()} %',
                  key: const Key('opacity_value'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                ),
                const Spacer(),
                const Text('100 %', style: TextStyle(fontSize: 13, color: _secondary)),
              ],
            ),
            SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: _accent,
                inactiveTrackColor: Color(0xFFE0E0E0),
                thumbColor: _accent,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                key: const Key('opacity_slider'),
                min: 0,
                max: 100,
                value: value.clamp(0, 100),
                onChanged: opacity == null
                    ? null
                    : (v) {
                        setState(() => _dragging = v / 100);
                        runLayerChange(context, () => preview(v / 100));
                      },
                onChangeEnd: opacity == null
                    ? null
                    : (v) => runLayerChange(context, () async {
                        await store(v / 100);
                        if (mounted) setState(() => _dragging = null);
                      }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
