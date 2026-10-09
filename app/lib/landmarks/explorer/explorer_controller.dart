import 'dart:convert';

import 'package:app/landmarks/services/folder_service.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/landmarks/settings/settings_keys.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'clipboard/landmarks_clipboard.dart';
import 'display/display_registry.dart';
import 'explorer_node.dart';
import 'explorer_state.dart';
import 'explorer_view_mode.dart';
import 'listing/filter_options.dart';
import 'listing/landmark_item.dart';
import 'listing/landmark_item_reader.dart';
import 'listing/sort_options.dart';
import 'places/place_root.dart';
import 'places/places_provider.dart';
import 'selection/selection_controller.dart';

/// Проводник меток: текущее место и папка, список, сортировка, фильтр и
/// вид. UI слушает его как [ChangeNotifier] и вызывает методы напрямую.
///
/// Decision: вместо репозитория и [StorageService] (их работа — в
/// [ExplorerOperations]) контроллер получает [AppSettings] — в них
/// хранятся вид (на папку), сортировка и фильтр (общие).
class ExplorerController extends ChangeNotifier {
  ExplorerController({
    required FolderService folders,
    required PlacesProvider places,
    required LandmarkItemReader reader,
    required DisplayRegistry displayRegistry,
    required SelectionController selection,
    required LandmarksClipboard clipboard,
    required AppSettings settings,
  }) : _folders = folders,
       _places = places,
       _reader = reader,
       _display = displayRegistry,
       _selection = selection,
       _clipboard = clipboard,
       _settings = settings {
    final sort = SortOptions.decode(_settings.getString(sortKey)) ?? const SortOptions();
    _appliedSort = sort.needsScreenCenter ? const SortOptions() : sort;
    _state = ExplorerState(sort: sort, filter: ItemFilter.decode(_settings.getString(filterKey)) ?? const ItemFilter());
    _display.addListener(_onDisplayChanged);
  }

  final FolderService _folders;
  final PlacesProvider _places;
  final LandmarkItemReader _reader;
  final DisplayRegistry _display;
  final SelectionController _selection;
  final LandmarksClipboard _clipboard;
  final AppSettings _settings;

  /// Ключи настроек сортировки и фильтра (общие для всех папок).
  static const String sortKey = '${SettingsKeys.sortPrefix}global';
  static const String filterKey = '${SettingsKeys.filterPrefix}global';

  late ExplorerState _state;

  /// Неотфильтрованное содержимое текущей папки.
  List<ExplorerFolderNode> _allFolders = const [];
  List<LandmarkItem> _allItems = const [];

  /// Сортировка, которая реально применена (может отличаться от
  /// `state.sort`, пока нет центра экрана).
  late SortOptions _appliedSort;
  ({double latitude, double longitude})? _center;
  int _loadToken = 0;

  ExplorerState get state => _state;
  SelectionController get selection => _selection;
  LandmarksClipboard get clipboard => _clipboard;
  DisplayRegistry get display => _display;

  /// Сортировка, по которой упорядочен список сейчас.
  SortOptions get appliedSort => _appliedSort;

  /// Все элементы текущей папки без фильтра (для статистики, «выбрать все»).
  List<LandmarkItem> get allItems => _allItems;

  /// Места для левого меню.
  Future<List<PlaceRoot>> loadPlaces() => _places.listPlaces();

  /// Открывает корень места.
  Future<void> openPlace(PlaceRoot place) async {
    _state = _state.copyWith(currentPlace: place);
    await openFolder(place.path);
  }

  /// Открывает папку: снимает выбор, читает содержимое, восстанавливает вид.
  Future<void> openFolder(String path) async {
    _selection.deactivate();
    final folder = p.normalize(path);
    _state = _state.copyWith(
      currentFolder: folder,
      viewMode: _savedViewMode(folder),
      isLoading: true,
      errorMessage: null,
    );
    notifyListeners();
    await _load(folder);
  }

  /// На уровень выше, но не выше корня текущего места.
  Future<void> goUp() async {
    final current = _state.currentFolder;
    if (current == null) return;
    final root = _state.currentPlace?.path;
    if (root != null && !_folders.isDescendant(root, current)) return;
    final parent = p.dirname(current);
    if (parent == current) return;
    await openFolder(parent);
  }

  /// Перечитывает текущую папку, не сбрасывая выбор.
  Future<void> refresh() async {
    final folder = _state.currentFolder;
    if (folder == null) return;
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();
    await _load(folder);
  }

  /// Вид списка для текущей папки; запоминается для неё.
  Future<void> setViewMode(ExplorerViewMode mode) async {
    _state = _state.copyWith(viewMode: mode);
    notifyListeners();
    final folder = _state.currentFolder;
    if (folder != null) await _settings.setString(viewModeKey(folder), mode.name);
  }

  /// Сортировка. По расстоянию без центра экрана список остаётся в
  /// прежнем порядке до [setScreenCenter].
  Future<void> setSort(SortOptions sort) async {
    _state = _state.copyWith(sort: sort);
    _applyView();
    await _settings.setString(sortKey, sort.encode());
  }

  /// Фильтр.
  Future<void> setFilter(ItemFilter filter) async {
    _state = _state.copyWith(filter: filter);
    _applyView();
    await _settings.setString(filterKey, filter.encode());
  }

  /// Центр карты для сортировки по расстоянию.
  Future<void> setScreenCenter(double lat, double lon) async {
    _center = (latitude: lat, longitude: lon);
    if (_state.sort.needsScreenCenter) _applyView();
  }

  /// Ключ настройки вида для [folder]: префикс + отпечаток пути.
  static String viewModeKey(String folder) =>
      '${SettingsKeys.viewModePrefix}${sha1.convert(utf8.encode(p.normalize(folder))).toString().substring(0, 16)}';

  Future<void> _load(String folder) async {
    final token = ++_loadToken;
    try {
      if (!await _folders.folderExists(folder)) throw StateError('Folder does not exist: $folder');
      final contents = await _folders.listContents(folder);
      final items = await _reader.readAll(folder);
      if (token != _loadToken) return;
      _allFolders = [for (final f in contents.folders) ExplorerFolderNode(path: f, name: p.basename(f))];
      _allItems = items;
      _state = _state.copyWith(isLoading: false);
    } on Object catch (e) {
      if (token != _loadToken) return;
      _allFolders = const [];
      _allItems = const [];
      _state = _state.copyWith(isLoading: false, errorMessage: e is StateError ? e.message : e.toString());
    }
    _applyView();
  }

  /// Применяет фильтр и сортировку к содержимому папки.
  void _applyView() {
    if (!_state.sort.needsScreenCenter || _center != null) _appliedSort = _state.sort;
    final filtered = FilterOptions(filter: _state.filter).apply(_allItems, display: _display.state);
    final sorted = _appliedSort.apply(filtered, center: _center);
    _state = _state.copyWith(nodes: [..._allFolders, for (final item in sorted) ExplorerItemNode(item)]);
    notifyListeners();
  }

  ExplorerViewMode _savedViewMode(String folder) {
    final saved = _settings.getString(viewModeKey(folder));
    return ExplorerViewMode.values.where((m) => m.name == saved).firstOrNull ?? ExplorerViewMode.preview;
  }

  void _onDisplayChanged() {
    if (_state.filter.onlyDisplayed) _applyView();
  }

  @override
  void dispose() {
    _display.removeListener(_onDisplayChanged);
    super.dispose();
  }
}
