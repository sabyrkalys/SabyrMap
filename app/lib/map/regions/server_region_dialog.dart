import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLngBounds;

import '../../format_bytes.dart';
import '../models/map_models.dart';
import 'regions_api.dart';
import 'server_region_service.dart';

class ServerRegionRequest {
  const ServerRegionRequest({required this.name, required this.maxZoom, required this.wifiOnly});

  final String name;
  final int maxZoom;
  final bool wifiOnly;
}

/// «Сохранить участок карты» for a map on our server: the visible area, a
/// max zoom, and the size check (server limit, free space) before saving.
class ServerRegionDialog extends ConsumerStatefulWidget {
  const ServerRegionDialog({super.key, required this.source, required this.bounds});

  final MapSource source;
  final LatLngBounds bounds;

  @override
  ConsumerState<ServerRegionDialog> createState() => _ServerRegionDialogState();
}

class _ServerRegionDialogState extends ConsumerState<ServerRegionDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.source.name);
  late int _maxZoom = ServerRegionService.defaultMaxZoom.clamp(widget.source.minZoom, _limit);
  bool _wifiOnly = true;
  RegionCheck? _check;
  String? _error;
  bool _checking = false;
  Timer? _debounce;
  int _request = 0;

  int get _limit => ServerRegionService.zoomLimit(widget.source);

  @override
  void initState() {
    super.initState();
    _recheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _recheck);
  }

  Future<void> _recheck() async {
    final request = ++_request;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final check = await ref
          .read(serverRegionServiceProvider)
          .check(source: widget.source, bounds: widget.bounds, maxZoom: _maxZoom);
      if (!mounted || request != _request) return;
      setState(() => _check = check);
    } on RegionException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _check = null;
        _error = e.message;
      });
    } finally {
      if (mounted && request == _request) setState(() => _checking = false);
    }
  }

  String? get _problem {
    final check = _check;
    if (_error != null) return _error;
    if (check == null) return null;
    if (!check.estimate.allowed) {
      return 'Больше ${formatBytes(check.estimate.maxBytes)} — уменьшите область или масштаб';
    }
    if (!check.fitsOnPhone) return 'Не хватает места на телефоне';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final problem = _problem;
    final canSave = !_checking && check != null && check.canSave && _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Сохранить участок карты'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('server_region_name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text('Область — то, что сейчас видно на карте'),
          const SizedBox(height: 8),
          Text('Подробность: до масштаба $_maxZoom'),
          Slider(
            key: const Key('server_region_zoom'),
            min: widget.source.minZoom.toDouble(),
            max: _limit.toDouble(),
            divisions: (_limit - widget.source.minZoom).clamp(1, 30),
            value: _maxZoom.toDouble(),
            onChanged: (v) {
              setState(() => _maxZoom = v.round());
              _scheduleCheck();
            },
          ),
          SizedBox(
            height: 40,
            child: _checking
                ? const Align(alignment: Alignment.centerLeft, child: LinearProgressIndicator())
                : Text(
                    key: const Key('server_region_size'),
                    [
                      if (check != null) 'Размер: ${formatBytes(check.estimate.totalBytes)}',
                      if (check?.freeBytes != null) 'свободно ${formatBytes(check!.freeBytes!)}',
                    ].join(' · '),
                  ),
          ),
          if (problem != null)
            Text(problem, key: const Key('server_region_problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          SwitchListTile(
            key: const Key('server_region_wifi'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Только по Wi-Fi'),
            value: _wifiOnly,
            onChanged: (v) => setState(() => _wifiOnly = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        TextButton(
          key: const Key('server_region_confirm'),
          onPressed: canSave
              ? () => Navigator.of(context)
                  .pop(ServerRegionRequest(name: _name.text.trim(), maxZoom: _maxZoom, wifiOnly: _wifiOnly))
              : null,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
