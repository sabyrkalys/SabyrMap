import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/landmarks/models/landmark_object.dart';
import 'package:app/landmarks/services/landmark_services.dart';

/// Окружение меню для [ContextMenuAction.labelResolver] и других
/// резолверов: сервисы и, в меню элемента, сам элемент и его содержимое.
class MenuEnv {
  const MenuEnv({required this.services, this.item, this.object});

  final LandmarkServices services;
  final LandmarkItem? item;

  /// Содержимое файла; null — меню секции или файл не прочитан.
  final LandmarkObject? object;
}
