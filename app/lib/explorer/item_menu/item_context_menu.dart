import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_object.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/landmark_services_provider.dart';
import '../context_menu_sheet.dart';
import '../descriptors/context_menu_section.dart';
import '../descriptors/descriptor_registry.dart';
import '../descriptors/menu_env.dart';

/// Меню элемента списка — из дескриптора его типа.
abstract final class ItemContextMenu {
  /// Пункты, которых нет в кратком меню (из детализации): объект уже
  /// открыт, а буфер и выбор работают в списке.
  static const Set<String> _notInCompact = {'details', 'open', 'copy', 'cut', 'select'};

  /// Пункты меню [item]; [compact] — краткое меню детализации.
  static List<ContextMenuSection> sectionsFor(BuildContext context, LandmarkItem item, {bool compact = false}) {
    final registry = ProviderScope.containerOf(context, listen: false).read(descriptorRegistryProvider);
    final sections = registry.of(item.type).buildItemMenu(context, item);
    if (!compact) return sections;
    return [
      for (final s in sections)
        ContextMenuSection(
          title: s.title,
          isRadio: s.isRadio,
          keepsOpen: s.keepsOpen,
          actions: [
            for (final a in s.actions)
              if (!_notInCompact.contains(a.id)) a,
          ],
        ),
    ];
  }

  /// Открывает меню. Содержимое файла читается заранее — от него зависят
  /// подписи некоторых пунктов («Замкнуть» / «Разомкнуть»).
  static Future<void> show(BuildContext context, LandmarkItem item, {bool compact = false}) async {
    final services = ProviderScope.containerOf(context, listen: false).read(landmarkServicesProvider);
    LandmarkObject? object;
    try {
      object = (await services.repository.load(item.path)).content;
    } on Exception {
      object = null;
    }
    if (!context.mounted) return;
    await ContextMenuSheet.show(
      context,
      key: Key(compact ? 'item_context_menu_compact' : 'item_context_menu'),
      title: item.name,
      sections: sectionsFor(context, item, compact: compact),
      env: MenuEnv(services: services, item: item, object: object),
      keyPrefix: 'item_menu',
    );
  }
}
