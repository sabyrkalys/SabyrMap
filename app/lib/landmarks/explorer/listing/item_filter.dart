import 'dart:convert';

import 'package:app/landmarks/explorer/display/display_state.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:collection/collection.dart';

import 'landmark_item.dart';

/// Фильтр списка проводника. Условия складываются по И; пустое условие
/// пропускает всё.
class ItemFilter {
  const ItemFilter({this.years = const {}, this.activities = const {}, this.onlyDisplayed = false, this.onlyType});

  /// Годы ([LandmarkItem.effectiveYear]); пусто — любые.
  final Set<int> years;

  /// Виды активности; пусто — любые. Элемент без активности проходит,
  /// только если фильтр по активности пуст.
  final Set<String> activities;

  /// Только объекты, показанные на карте.
  final bool onlyDisplayed;

  /// Только этот тип; null — любой.
  final LandmarkType? onlyType;

  bool get isEmpty => years.isEmpty && activities.isEmpty && !onlyDisplayed && onlyType == null;

  /// Проходит ли [item]. [display] нужен для [onlyDisplayed].
  bool matches(LandmarkItem item, {DisplayState display = const DisplayState()}) {
    if (years.isNotEmpty && !years.contains(item.effectiveYear)) return false;
    if (activities.isNotEmpty && !activities.contains(item.activity)) return false;
    if (onlyDisplayed && !display.isDisplayed(item.path)) return false;
    if (onlyType != null && item.type != onlyType) return false;
    return true;
  }

  static const Object _keep = Object();

  /// Копия с заменёнными полями; `onlyType: null` снимает фильтр по типу.
  ItemFilter copyWith({Set<int>? years, Set<String>? activities, bool? onlyDisplayed, Object? onlyType = _keep}) =>
      ItemFilter(
        years: years ?? this.years,
        activities: activities ?? this.activities,
        onlyDisplayed: onlyDisplayed ?? this.onlyDisplayed,
        onlyType: identical(onlyType, _keep) ? this.onlyType : onlyType as LandmarkType?,
      );

  /// JSON для настроек.
  String encode() => jsonEncode({
    'years': (years.toList()..sort()),
    'activities': (activities.toList()..sort()),
    'onlyDisplayed': onlyDisplayed,
    'onlyType': onlyType?.extension,
  });

  /// Обратно из [encode]; повреждённая строка — null.
  static ItemFilter? decode(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return ItemFilter(
        years: {for (final y in json['years'] as List<dynamic>) y as int},
        activities: {for (final a in json['activities'] as List<dynamic>) a as String},
        onlyDisplayed: json['onlyDisplayed'] as bool,
        onlyType: switch (json['onlyType']) {
          final String ext => LandmarkType.fromExtension(ext),
          _ => null,
        },
      );
    } on Object {
      return null;
    }
  }

  static const _set = SetEquality<Object?>();

  @override
  bool operator ==(Object other) =>
      other is ItemFilter &&
      _set.equals(other.years, years) &&
      _set.equals(other.activities, activities) &&
      other.onlyDisplayed == onlyDisplayed &&
      other.onlyType == onlyType;

  @override
  int get hashCode => Object.hash(_set.hash(years), _set.hash(activities), onlyDisplayed, onlyType);
}
