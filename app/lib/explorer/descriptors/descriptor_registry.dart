import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'landmark_type_descriptor.dart';
import 'type_descriptors.dart';

/// Дескрипторы типов меток.
class DescriptorRegistry {
  final Map<LandmarkType, LandmarkTypeDescriptor> _byType = {};

  /// Регистрирует дескриптор; тот же тип заменяет прежний.
  void register(LandmarkTypeDescriptor descriptor) => _byType[descriptor.type] = descriptor;

  LandmarkTypeDescriptor? byType(LandmarkType type) => _byType[type];

  /// Дескриптор типа; незарегистрированный тип — [StateError].
  LandmarkTypeDescriptor of(LandmarkType type) =>
      _byType[type] ?? (throw StateError('No descriptor for ${type.name}'));

  /// Все дескрипторы в порядке регистрации.
  List<LandmarkTypeDescriptor> get all => List.unmodifiable(_byType.values);

  /// Все типы, в порядке секций списка.
  static DescriptorRegistry buildDefault() {
    final registry = DescriptorRegistry();
    for (final d in TypeDescriptors.all()) {
      registry.register(d);
    }
    return registry;
  }
}

/// Реестр дескрипторов приложения.
///
/// Decision: живёт в riverpod, а не в LandmarkServices — дескрипторы
/// строят виджеты и меню, а LandmarkServices остаются слоем без UI.
final descriptorRegistryProvider = Provider<DescriptorRegistry>((ref) => DescriptorRegistry.buildDefault());
