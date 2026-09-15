import 'package:flutter/material.dart';

import '../compass/compass_screen.dart';
import '../map/map_screen.dart';
import '../settings/settings_screen.dart';
import '../waypoints/waypoints_list_screen.dart';

/// Bottom-nav shell with the app's four top-level destinations. Uses
/// [IndexedStack] rather than swapping widgets so MapScreen's state (GPS
/// position, in-progress track recording, MapLibre controller) survives
/// switching to another tab and back.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    MapScreen(),
    WaypointsListScreen(),
    CompassScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(key: Key('nav_map'), icon: Icon(Icons.map), label: 'Карты'),
          NavigationDestination(key: Key('nav_waypoints'), icon: Icon(Icons.location_on), label: 'Метки'),
          NavigationDestination(key: Key('nav_compass'), icon: Icon(Icons.explore), label: 'Компас'),
          NavigationDestination(key: Key('nav_settings'), icon: Icon(Icons.tune), label: 'Настройки'),
        ],
      ),
    );
  }
}
