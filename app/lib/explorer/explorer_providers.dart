import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/regions/server_region_service.dart';

/// Размер и свободное место разделов (подменяется в тестах).
final storageInfoProvider = Provider<StorageInfo>((ref) => const PlatformStorageInfo());
