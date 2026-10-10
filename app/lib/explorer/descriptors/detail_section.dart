import 'package:flutter/widgets.dart';

import 'detail_data.dart';
import 'detail_field.dart';

/// Сворачиваемая секция детализации: «ФАЙЛ», «СТАТИСТИКА»...
class DetailSection {
  const DetailSection({
    required this.title,
    this.initiallyExpanded = true,
    this.fields = const [],
    this.customBody,
  });

  final String title;
  final bool initiallyExpanded;
  final List<DetailField> fields;

  /// Своё тело вместо строк (списки точек, сегментов, плеч).
  final Widget Function(BuildContext context, LandmarkDetailsData data)? customBody;
}
