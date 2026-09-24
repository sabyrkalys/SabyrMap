import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_icons.dart';
import '../compass/compass_screen.dart';
import '../map/map_screen.dart';
import '../positioning/positioning_screen.dart';
import '../settings/settings_screen.dart';
import '../system_ui.dart';
import '../waypoints/waypoints_list_screen.dart';
import '../widgets/app_icon.dart';

/// Bottom-nav shell with the app's five top-level destinations. Uses
/// [IndexedStack] rather than swapping widgets so MapScreen's state (GPS
/// position, in-progress track recording, MapLibre controller) survives
/// switching to another tab and back.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _mapIndex = 1;

  int _index = _mapIndex;

  static const _screens = [
    SettingsScreen(),
    MapScreen(),
    WaypointsListScreen(),
    PositioningScreen(),
    CompassScreen(),
  ];

  static const _destinations = [
    _NavDestination(key: Key('nav_settings'), icon: AppIcons.peakMark, label: 'Настройки'),
    _NavDestination(key: Key('nav_map'), icon: AppIcons.map, label: 'Карты'),
    _NavDestination(key: Key('nav_waypoints'), icon: AppIcons.flag, label: 'Метки'),
    _NavDestination(key: Key('nav_positioning'), icon: AppIcons.target, label: 'Позиционирование'),
    _NavDestination(key: Key('nav_compass'), icon: AppIcons.compass, label: 'Компас'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemNavigationBarStyle(Theme.of(context).brightness),
      child: Scaffold(
        // The nav panel is half transparent and doesn't span the full width,
        // so the tab content (the map) must continue underneath it.
        extendBody: true,
        body: IndexedStack(index: _index, children: _screens),
        bottomNavigationBar: _BottomNav(
          destinations: _destinations,
          selectedIndex: _index,
          onSelected: (index) => setState(() => _index = index),
        ),
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination({required this.key, required this.icon, required this.label});

  final Key key;
  final String icon;
  final String label;
}

/// Compact bottom nav: a half-transparent 60 dp panel sitting 5 dp from the
/// left screen edge, sized to its 40 dp icons (10 dp gap between them and
/// 5 dp to the panel edge). Material's [NavigationBar] always spreads
/// destinations across the full width, hence the custom widget.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.destinations, required this.selectedIndex, required this.onSelected});

  static const double _height = 60;
  static const double _iconSize = 40;
  static const double _gap = 10;
  static const double _indicatorSize = 48;
  static const double _screenMargin = 5;
  static const double _backgroundOpacity = 0.5;

  /// Each item is icon + gap wide, so half a gap sits on either side of the
  /// icon (5 dp to the panel edge for the outer ones).
  static const double _itemWidth = _iconSize + _gap;

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: _screenMargin),
        child: Align(
          alignment: Alignment.bottomLeft,
          heightFactor: 1,
          child: Container(
            key: const Key('bottom_nav'),
            height: _height,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer.withValues(alpha: _backgroundOpacity),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _buildItem(
                      destinations[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                      colorScheme: colorScheme,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    _NavDestination destination, {
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Semantics(
      key: destination.key,
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        child: InkResponse(
          onTap: onTap,
          radius: _indicatorSize / 2,
          child: SizedBox(
            width: _itemWidth,
            height: _height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (selected)
                  Container(
                    key: const Key('nav_indicator'),
                    width: _indicatorSize,
                    height: _indicatorSize,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                AppIcon(
                  destination.icon,
                  size: _iconSize,
                  color: selected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
