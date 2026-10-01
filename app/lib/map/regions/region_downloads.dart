import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLngBounds;

import '../catalog/catalog_repository.dart';
import '../models/map_models.dart';
import 'file_downloader.dart';
import 'regions_api.dart';
import 'server_region_service.dart';

enum RegionDownloadState { running, done, failed, cancelled }

/// One offline region being fetched from the server, as the UI shows it.
class RegionDownload {
  const RegionDownload({
    required this.key,
    required this.name,
    required this.state,
    this.label = 'Ожидание сервера',
    this.fraction,
    this.error,
  });

  final int key;
  final String name;
  final RegionDownloadState state;

  /// What is happening now: «Сервер готовит участок», «Скачивание», …
  final String label;

  /// 0–1, null when unknown.
  final double? fraction;
  final String? error;

  RegionDownload copyWith({RegionDownloadState? state, String? label, double? fraction, String? error}) =>
      RegionDownload(
        key: key,
        name: name,
        state: state ?? this.state,
        label: label ?? this.label,
        fraction: fraction ?? this.fraction,
        error: error ?? this.error,
      );
}

/// Server region downloads of this app session. They keep running when the
/// screen that started them closes; a finished one appears in «Установленные
/// карты» (the catalog is reloaded).
class RegionDownloadsNotifier extends Notifier<List<RegionDownload>> {
  final Map<int, CancelToken> _tokens = {};
  int _next = 0;

  @override
  List<RegionDownload> build() => const [];

  void _update(int key, RegionDownload Function(RegionDownload) change) {
    state = [for (final d in state) d.key == key ? change(d) : d];
  }

  static String _label(RegionProgress p, {bool overview = false}) {
    final what = switch (p.stage) {
      RegionStage.preparing => 'Сервер готовит участок',
      RegionStage.downloading => 'Скачивание',
      RegionStage.installing => 'Установка',
    };
    return overview ? '${ServerRegionService.overviewFolderName}: $what' : what;
  }

  /// Starts fetching a region; returns at once (the progress is in [state]).
  void start({
    required MapSource source,
    required LatLngBounds bounds,
    required int maxZoom,
    required String name,
    required bool wifiOnly,
  }) {
    final key = _next++;
    final cancel = _tokens[key] = CancelToken();
    state = [...state, RegionDownload(key: key, name: name, state: RegionDownloadState.running)];
    Future<void>(() async {
      final service = ref.read(serverRegionServiceProvider);
      try {
        // The world overview package comes with the first vector region.
        if (source.format == TileFormat.vector) {
          final overviewSource = await _overviewSource();
          if (overviewSource != null) {
            await service.ensureOverview(
              source: overviewSource,
              wifiOnly: wifiOnly,
              cancel: cancel,
              onProgress: (p) => _update(key, (d) => d.copyWith(label: _label(p, overview: true), fraction: p.fraction)),
            );
          }
        }
        await service.install(
          source: source,
          bounds: bounds,
          maxZoom: maxZoom,
          name: name,
          wifiOnly: wifiOnly,
          cancel: cancel,
          onProgress: (p) => _update(key, (d) => d.copyWith(label: _label(p), fraction: p.fraction)),
        );
        _update(key, (d) => d.copyWith(state: RegionDownloadState.done, label: 'Готово', fraction: 1));
        await ref.read(catalogProvider.notifier).reload();
      } on DownloadCancelled {
        _update(key, (d) => d.copyWith(state: RegionDownloadState.cancelled, label: 'Отменено'));
      } on RegionException catch (e) {
        _update(key, (d) => d.copyWith(state: RegionDownloadState.failed, label: 'Ошибка', error: e.message));
      } catch (e) {
        _update(key, (d) => d.copyWith(state: RegionDownloadState.failed, label: 'Ошибка', error: '$e'));
      } finally {
        _tokens.remove(key);
      }
    });
  }

  Future<MapSource?> _overviewSource() async {
    for (final provider in await ref.read(catalogProvider.future)) {
      for (final s in provider.sources) {
        if (s.id == CatalogRepository.serverHybridSourceId && s.downloadable) return s;
      }
    }
    return null;
  }

  void cancel(int key) => _tokens[key]?.cancel();

  /// Removes a finished, failed or cancelled entry from the list.
  void dismiss(int key) => state = [for (final d in state) if (d.key != key || d.state == RegionDownloadState.running) d];
}

final regionDownloadsProvider =
    NotifierProvider<RegionDownloadsNotifier, List<RegionDownload>>(RegionDownloadsNotifier.new);
