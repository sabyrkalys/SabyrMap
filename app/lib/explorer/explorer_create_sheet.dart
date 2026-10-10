import 'package:flutter/material.dart';

import '../waypoints/new_marker/marker_type.dart';
import '../waypoints/new_marker/marker_type_item.dart';
import '../waypoints/new_marker/new_marker_sheet.dart';
import '../waypoints/new_marker/section_header.dart';

/// Что создаётся в папке, кроме меток с листа «Новая метка».
abstract final class ExplorerCreateIds {
  static const folder = 'folder';
  static const landmarkFile = 'landmark_file';
  static const import = 'import';
}

/// Пункты раздела «Папки и файлы».
const List<MarkerType> explorerFileTypes = [
  MarkerType(
    id: ExplorerCreateIds.folder,
    title: 'Папка',
    subtitle: 'Создать папку в текущей папке.',
    icon: Icons.create_new_folder_outlined,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: ExplorerCreateIds.landmarkFile,
    title: 'Файл меток',
    subtitle: 'Создать файл меток .ldk: только имя, формат подставляется сам.',
    icon: Icons.note_add_outlined,
    category: MarkerCategory.local,
  ),
  MarkerType(
    id: ExplorerCreateIds.import,
    title: 'Импорт файла',
    subtitle: 'Добавить метки из файла GPX, KML, CSV или GeoJSON.',
    icon: Icons.file_download_outlined,
    category: MarkerCategory.local,
  ),
];

/// Лист «Создать» проводника в оформлении «Новой метки»: папки и файлы,
/// затем все виды локальных меток. Возвращает выбранный пункт.
Future<MarkerType?> showExplorerCreateSheet(BuildContext context) => showModalBottomSheet<MarkerType>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: NewMarkerSheet.background,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
  builder: (context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      key: const Key('explorer_create_sheet'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text('Создать', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
          ),
          const SectionHeader(label: 'Папки и файлы'),
          for (final type in explorerFileTypes)
            MarkerTypeItem(type: type, onTap: () => Navigator.of(context).pop(type)),
          const SectionHeader(label: 'Локальные метки'),
          for (final type in markerTypes.where((t) => t.category == MarkerCategory.local))
            MarkerTypeItem(type: type, onTap: () => Navigator.of(context).pop(type)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('explorer_create_cancel'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: NewMarkerSheet.cancelColor),
              child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    ),
  ),
);
