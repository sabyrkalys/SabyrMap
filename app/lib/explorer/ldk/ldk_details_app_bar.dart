import 'package:flutter/material.dart';

import '../../map/screens/available_maps/maps_app_bar.dart';

/// Шапка детализации — как у «Локальных меток»: ☰ | «Локальные метки» над
/// именем файла | ✕, ⋮.
class LdkDetailsAppBar extends StatelessWidget {
  const LdkDetailsAppBar({
    super.key,
    required this.displayName,
    required this.onMenu,
    required this.onClose,
    required this.onMore,
  });

  final String displayName;

  /// ☰ — боковая панель проводника.
  final VoidCallback onMenu;
  final VoidCallback onClose;

  /// ⋮ — краткое меню файла.
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => MapsAppBar(
    title: 'Локальные метки',
    subtitle: displayName,
    onMenu: onMenu,
    onClose: onClose,
    onMore: onMore,
  );
}
