import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../mediafile/mediafile_folder_service.dart';
import '../../../mediafile/mediafile_subfolders.dart';
import '../../catalog/catalog_repository.dart';
import '../../regions/server_region_service.dart';
import 'available_maps_models.dart';

/// Used and total space of the volume with mediafile/maps; null when the
/// platform can't tell. Re-read whenever the catalog changes (a map
/// installed or deleted).
final deviceStorageProvider = FutureProvider<StorageUsage?>((ref) async {
  await ref.watch(catalogProvider.future);
  return readDeviceStorage(MediaFileFolderService(subfolder: kMapsSubfolder), const PlatformStorageInfo());
});

Future<StorageUsage?> readDeviceStorage(MediaFileFolderService mapsFolder, StorageInfo storage) async {
  try {
    final path = (await mapsFolder.directory()).path;
    final total = await storage.totalBytes(path);
    final free = await storage.freeBytes(path);
    if (total == null || free == null || total <= 0) return null;
    return StorageUsage(path: path, usedBytes: total - free, totalBytes: total);
  } catch (_) {
    return null;
  }
}
