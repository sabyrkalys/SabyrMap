import 'dart:io';

import 'package:app/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

import 'aqx_descriptor.dart';
import 'aqx_parser.dart';
import 'aqx_store.dart';

/// Онлайн-карты: файлы `*.aqx` из `<корень>/datastore/maps` плюс описания,
/// сохранённые в [AqxStore]. Разобранное кэшируется до [refresh].
class AqxRegistry {
  AqxRegistry(this._paths, {AqxParser parser = const AqxParser(), AqxStore? store}) : _parser = parser, _store = store;

  final StoragePaths _paths;
  final AqxParser _parser;
  final AqxStore? _store;
  List<AqxDescriptor> _all = const [];
  List<String> _errors = const [];

  List<AqxDescriptor> get all => _all;

  /// Файлы, которые не удалось разобрать при последнем [refresh].
  List<String> get errors => _errors;

  AqxDescriptor? byId(String id) => _all.where((d) => d.id == id).firstOrNull;

  /// Перечитывает папку (без подпапок). Описание из файла с тем же id
  /// заменяет сохранённое.
  Future<void> refresh() async {
    final byId = <String, AqxDescriptor>{for (final d in await _store?.loadAll() ?? const <AqxDescriptor>[]) d.id: d};
    final errors = <String>[];
    final dir = Directory(_paths.datastoreMaps);
    if (await dir.exists()) {
      final files = [
        await for (final e in dir.list(followLinks: false))
          if (e is File && p.extension(e.path).toLowerCase() == '.aqx') e.path,
      ]..sort();
      for (final path in files) {
        try {
          final d = await _parser.parseFile(path);
          byId[d.id] = d;
        } on FormatException catch (e) {
          errors.add('${p.basename(path)}: ${e.message}');
        }
      }
    }
    _all = List.unmodifiable(byId.values);
    _errors = List.unmodifiable(errors);
  }
}
