import 'erase_color_settings.dart';

/// Стирание цвета (без состояния).
class EraseColorController {
  const EraseColorController();

  /// Пиксель стирается, если стирание включено и каждый диапазон содержит
  /// значение своего канала. Без диапазонов не стирается ничего.
  static bool shouldErase(int argb, EraseColorSettings settings) {
    if (!settings.enabled || settings.ranges.isEmpty) return false;
    return settings.ranges.every((r) => r.contains(r.channelOf(argb)));
  }

  /// Пиксель с нулевой альфой, если его нужно стереть; иначе как есть.
  static int withErasedAlpha(int argb, EraseColorSettings settings) =>
      shouldErase(argb, settings) ? argb & 0x00FFFFFF : argb;
}
