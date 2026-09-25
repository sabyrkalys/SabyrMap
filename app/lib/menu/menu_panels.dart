import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_icons.dart';
import '../compass/compass_screen.dart';
import '../tracks/track_recording_actions.dart';
import '../tracks/track_recording_controller.dart';
import '../waypoints/waypoint_create_action.dart';
import '../waypoints/waypoints_list_screen.dart';
import 'menu_toggles.dart';
import 'menu_widgets.dart';

/// Bottom-nav destinations, in nav order; each opens its own panel.
enum MenuTab { settings, maps, waypoints, positioning, orientation }

Widget menuPanelFor(MenuTab tab, {required double arrowCenterX}) {
  return switch (tab) {
    MenuTab.settings => _SettingsPanel(arrowCenterX: arrowCenterX),
    MenuTab.maps => _MapsPanel(arrowCenterX: arrowCenterX),
    MenuTab.waypoints => _WaypointsPanel(arrowCenterX: arrowCenterX),
    MenuTab.positioning => _PositioningPanel(arrowCenterX: arrowCenterX),
    MenuTab.orientation => _OrientationPanel(arrowCenterX: arrowCenterX),
  };
}

/// Checkbox bound to one persisted [MenuToggle].
class _ToggleCheckbox extends ConsumerWidget {
  const _ToggleCheckbox(this.toggle, this.label);

  final MenuToggle toggle;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuCheckboxItem(
      label: label,
      value: ref.watch(menuTogglesProvider)[toggle]!,
      onChanged: (value) => ref.read(menuTogglesProvider.notifier).set(toggle, value),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      key: const Key('settings_panel'),
      title: 'НАСТРОЙКИ',
      arrowCenterX: arrowCenterX,
      items: const [
        MenuListItem(icon: AppIcons.fullscreen, label: 'Скрыть кнопки меню'),
        MenuListItem(icon: AppIcons.lock, label: 'Блокировка экрана'),
        MenuListItem(icon: AppIcons.camera, label: 'Снимок экрана'),
        MenuListItem(icon: AppIcons.settings, label: 'Настройки'),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.settingsSk42Grid, 'Координатная сетка СК-42 (Гаусса-Крюгера)'),
          _ToggleCheckbox(MenuToggle.settingsNightMode, 'Ночной режим'),
          _ToggleCheckbox(MenuToggle.settingsCenterCoordinates, 'Координаты центра экрана'),
        ]),
      ],
    );
  }
}

class _MapsPanel extends StatelessWidget {
  const _MapsPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      key: const Key('maps_panel'),
      title: 'КАРТЫ',
      arrowCenterX: arrowCenterX,
      items: const [
        MenuListItem(icon: AppIcons.folderMap, label: 'Доступные карты'),
        MenuListItem(icon: AppIcons.layers, label: 'Карты на экране'),
        MenuListItem(icon: AppIcons.download, label: 'Сохранить участок карты'),
        MenuListItem(icon: AppIcons.star, label: 'Избранные карты'),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.mapsCacheOnly, 'Использовать только сохранённый кэш карты'),
          _ToggleCheckbox(MenuToggle.mapsLoadingIndicators, 'Индикаторы загрузки карты'),
          _ToggleCheckbox(MenuToggle.mapsMapName, 'Название карты'),
          _ToggleCheckbox(MenuToggle.mapsMapScale, 'Масштаб карты'),
          _ToggleCheckbox(MenuToggle.mapsScaleBar, 'Масштабная линейка'),
        ]),
      ],
    );
  }
}

class _WaypointsPanel extends ConsumerWidget {
  const _WaypointsPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuPanel(
      key: const Key('waypoints_panel'),
      title: 'МЕТКИ',
      arrowCenterX: arrowCenterX,
      items: [
        MenuListItem(
          icon: AppIcons.flag,
          label: 'Все метки',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WaypointsListScreen())),
        ),
        const MenuListItem(icon: AppIcons.list, label: 'Метки на экране'),
        MenuListItem(
          icon: AppIcons.flagPlus,
          label: 'Новая метка',
          onTap: () => createWaypointAtCrosshair(context, ref),
        ),
        const MenuListItem(icon: AppIcons.search, label: 'Поиск на карте'),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.waypointsNames, 'Названия меток'),
          _ToggleCheckbox(MenuToggle.waypointsTargetLine, 'Линия до цели'),
        ]),
        MenuSection(title: 'ИНФОРМЕРЫ', children: [
          _ToggleCheckbox(MenuToggle.waypointsTargetStatus, 'Статус цели'),
        ]),
      ],
    );
  }
}

class _PositioningPanel extends ConsumerWidget {
  const _PositioningPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(trackRecordingControllerProvider);
    final toggles = ref.watch(menuTogglesProvider);
    return MenuPanel(
      key: const Key('positioning_panel'),
      title: 'ПОЗИЦИОНИРОВАНИЕ',
      arrowCenterX: arrowCenterX,
      items: [
        const MenuListItem(icon: AppIcons.gauge, label: 'Путевой компьютер'),
        MenuSwitchItem(
          label: 'Геолокация',
          value: toggles[MenuToggle.positioningGeolocation]!,
          onChanged: (value) => ref.read(menuTogglesProvider.notifier).set(MenuToggle.positioningGeolocation, value),
        ),
        MenuSwitchItem(
          key: const Key('track_record_toggle'),
          label: 'Запись трека',
          value: recordingState is TrackRecordingActive,
          onChanged: (_) => toggleTrackRecording(context, ref, recordingState),
        ),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.positioningRotateByMovement, 'Вращать карту по движению'),
          _ToggleCheckbox(MenuToggle.positioningDistanceLine, 'Линия расстояния'),
        ]),
        MenuSection(title: 'ИНФОРМЕРЫ', children: [
          _ToggleCheckbox(MenuToggle.positioningStatus, 'Статус позиционирования'),
          _ToggleCheckbox(MenuToggle.positioningRecordingStatus, 'Статус записи трека'),
        ]),
      ],
    );
  }
}

/// The «Компас» switch is on while CompassScreen is open and goes off when
/// the user leaves it; it is not persisted.
class _OrientationPanel extends StatefulWidget {
  const _OrientationPanel({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  State<_OrientationPanel> createState() => _OrientationPanelState();
}

class _OrientationPanelState extends State<_OrientationPanel> {
  bool _compassOpen = false;

  Future<void> _openCompass() async {
    setState(() => _compassOpen = true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompassScreen()));
    if (mounted) setState(() => _compassOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      key: const Key('orientation_panel'),
      title: 'ОРИЕНТИРОВАНИЕ',
      arrowCenterX: widget.arrowCenterX,
      items: [
        MenuSwitchItem(
          key: const Key('compass_switch'),
          icon: AppIcons.compass,
          label: 'Компас',
          value: _compassOpen,
          onChanged: (value) {
            if (value && !_compassOpen) _openCompass();
          },
        ),
      ],
      sections: const [
        MenuSection(title: 'ОПЦИИ', children: [
          _ToggleCheckbox(MenuToggle.orientationRotateByCompass, 'Вращать карту по компасу'),
          _ToggleCheckbox(MenuToggle.orientationShowCompass, 'Показать компас'),
        ]),
        MenuSection(title: 'ИНФОРМЕРЫ', children: [
          _ToggleCheckbox(MenuToggle.orientationCompassStatus, 'Статус компаса'),
        ]),
      ],
    );
  }
}
