import 'package:app/landmarks/composite/distance/haversine.dart';
import 'package:app/navigation/position/position_snapshot.dart';
import 'package:app/navigation/position/position_source.dart';
import 'package:app/navigation/signals/audio_signaler.dart';
import 'package:app/navigation/target/target_controller.dart';
import 'package:flutter/foundation.dart';

import 'proximity_alert.dart';
import 'proximity_alert_calculator.dart';
import 'proximity_alert_signal.dart';
import 'proximity_alert_state.dart';
import 'proximity_alert_store.dart';
import 'proximity_zone.dart';

/// Оповещения о приближении: список, зоны, сигналы при переходах, цель во
/// внутренней зоне. Фоновая работа — забота платформенного слоя; здесь
/// оповещения и зоны сохраняются, чтобы восстановиться при старте.
class ProximityAlertController extends ChangeNotifier {
  ProximityAlertController(
    this._store,
    this._position,
    AudioSignaler signaler,
    this._target, {
    ProximityAlertSignalEmitter? emitter,
  }) : _emitter = emitter ?? ProximityAlertSignalEmitter(signaler);

  /// Рабочее пространство до первого [load].
  static const String defaultWorkspace = 'default';

  final ProximityAlertStore _store;
  final PositionSource _position;
  final TargetController _target;
  final ProximityAlertSignalEmitter _emitter;

  String _workspace = defaultWorkspace;
  List<ProximityAlert> _alerts = const [];
  ProximityAlertState _state = const ProximityAlertState();

  /// Оповещения, которые хоть раз были внутри радиуса с момента загрузки.
  final Set<String> _entered = {};

  List<ProximityAlert> get alerts => _alerts;
  ProximityAlertState get state => _state;
  String get workspaceId => _workspace;

  /// Загружает оповещения и зоны рабочего пространства.
  Future<void> load(String workspaceId) async {
    await _emitter.stopAll();
    _workspace = workspaceId;
    _alerts = List.unmodifiable(await _store.load(workspaceId));
    final zones = await _store.loadZones(workspaceId);
    final ids = {for (final a in _alerts) if (a.isActive) a.id};
    _state = ProximityAlertState(currentZones: Map.unmodifiable({
      for (final e in zones.entries) if (ids.contains(e.key)) e.key: e.value,
    }));
    _entered
      ..clear()
      ..addAll([for (final e in _state.currentZones.entries) if (e.value.isInside) e.key]);
    notifyListeners();
  }

  /// Добавляет оповещение и сразу проверяет его по текущему положению.
  Future<void> add(ProximityAlert alert) async {
    _alerts = List.unmodifiable([..._alerts.where((a) => a.id != alert.id), alert]);
    await _store.save(_workspace, _alerts);
    notifyListeners();
    final position = await _position.getCurrent();
    if (position != null) await updatePosition(position);
  }

  Future<void> remove(String alertId) async {
    _alerts = List.unmodifiable(_alerts.where((a) => a.id != alertId));
    await _store.save(_workspace, _alerts);
    await _forget(alertId);
    notifyListeners();
  }

  /// Заменяет оповещение; выключенное убирается из зон.
  Future<void> update(ProximityAlert alert) async {
    _alerts = List.unmodifiable([for (final a in _alerts) a.id == alert.id ? alert : a]);
    await _store.save(_workspace, _alerts);
    if (!alert.isActive) await _forget(alert.id);
    notifyListeners();
  }

  /// Для каждого включённого оповещения: зона, сигнал при переходе, цель
  /// во внутренней зоне ([ProximityAlert.setAsTarget]).
  Future<void> updatePosition(PositionSnapshot snapshot) async {
    if (!snapshot.isValid) return;
    final zones = Map.of(_state.currentZones);
    var changed = false;
    for (final alert in _alerts.where((a) => a.isActive)) {
      final to = ProximityAlertCalculator.zone(
        distanceMeters: Haversine.distance(snapshot.location, alert.center),
        radiusMeters: alert.radiusMeters,
      );
      final from = zones[alert.id] ?? ProximityZone.outside;
      if (to == from && zones.containsKey(alert.id)) continue;
      changed = true;
      final kind = ProximityAlertCalculator.signalFor(from: from, to: to, wasInside: _entered.contains(alert.id));
      _emitter.onTransition(alert.id, kind, repeat: alert.repeatNotifications);
      if (to.isInside) _entered.add(alert.id);
      if (to == ProximityZone.outside) _entered.remove(alert.id);
      zones[alert.id] = to;
      if (alert.setAsTarget && to == ProximityZone.inner && from != ProximityZone.inner) {
        await _target.setTarget(alert.center);
      }
    }
    if (!changed) return;
    _state = _state.copyWith(currentZones: zones);
    await _store.saveZones(_workspace, _state.currentZones);
    notifyListeners();
  }

  Future<void> _forget(String alertId) async {
    _emitter.cancel(alertId);
    _entered.remove(alertId);
    if (!_state.currentZones.containsKey(alertId)) return;
    _state = _state.copyWith(currentZones: Map.of(_state.currentZones)..remove(alertId));
    await _store.saveZones(_workspace, _state.currentZones);
  }

  @override
  void dispose() {
    _emitter.stopAll();
    super.dispose();
  }
}
