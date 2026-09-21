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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(key: Key('nav_settings'), icon: AppIcon(AppIcons.peakMark), label: 'Настройки'),
          NavigationDestination(key: Key('nav_map'), icon: AppIcon(AppIcons.map), label: 'Карты'),
          NavigationDestination(key: Key('nav_waypoints'), icon: AppIcon(AppIcons.flag), label: 'Метки'),
          NavigationDestination(key: Key('nav_positioning'), icon: AppIcon(AppIcons.target), label: 'Позиционирование'),
          NavigationDestination(key: Key('nav_compass'), icon: AppIcon(AppIcons.compass), label: 'Компас'),
        ],
      ),
    );
  }
}
