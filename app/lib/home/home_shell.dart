import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../compass/compass_screen.dart';
import '../map/map_screen.dart';
import '../positioning/positioning_screen.dart';
import '../settings/settings_screen.dart';
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
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _BottomNav(
        destinations: _destinations,
        selectedIndex: _index,
        onSelected: (index) => setState(() => _index = index),
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

/// Compact bottom nav: 60 dp tall, 40 dp icons packed against the left edge
/// with a 10 dp gap (and 10 dp from the screen edge). Material's
/// [NavigationBar] always spreads destinations across the full width, hence
/// the custom widget.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.destinations, required this.selectedIndex, required this.onSelected});

  static const double _height = 60;
  static const double _iconSize = 40;
  static const double _gap = 10;
  static const double _indicatorSize = 48;

  /// Each item is icon + gap wide, so half a gap sits on either side of the
  /// icon; the outer half-gap padding makes the edge margin a full gap.
  static const double _itemWidth = _iconSize + _gap;

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const Key('bottom_nav'),
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  _buildItem(destinations[i], selected: i == selectedIndex, onTap: () => onSelected(i), colorScheme: colorScheme),
              ],
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
