import 'landmark_location.dart';
import 'landmark_metadata.dart';
import 'landmark_object.dart';
import 'landmark_type.dart';

/// Текст на карте (файл `.lbl`): точка привязки и надпись.
///
/// Decision: размер и поворот надписи — оформление, они живут в
/// метаданных (как цвет), а не в содержимом: [textSizeKey], [rotationKey].
class TextObject extends LandmarkObject {
  const TextObject({
    required this.location,
    required this.text,
    this.userMetadata = const LandmarkMetadata(),
    this.technicalMetadata = const LandmarkMetadata(),
  });

  /// Размер надписи, sp.
  static const String textSizeKey = 'text_size';

  /// Поворот надписи, градусы по часовой от горизонтали.
  static const String rotationKey = 'rotation';

  final LandmarkLocation location;

  /// Надпись; не пустая.
  final String text;

  @override
  final LandmarkMetadata userMetadata;

  @override
  final LandmarkMetadata technicalMetadata;

  @override
  LandmarkType get type => LandmarkType.text;

  TextObject copyWith({LandmarkLocation? location, String? text}) => TextObject(
    location: location ?? this.location,
    text: text ?? this.text,
    userMetadata: userMetadata,
    technicalMetadata: technicalMetadata,
  );

  @override
  TextObject withUserMetadata(LandmarkMetadata userMetadata) =>
      TextObject(location: location, text: text, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  @override
  TextObject withTechnicalMetadata(LandmarkMetadata technicalMetadata) =>
      TextObject(location: location, text: text, userMetadata: userMetadata, technicalMetadata: technicalMetadata);

  @override
  bool operator ==(Object other) =>
      other is TextObject &&
      other.location == location &&
      other.text == text &&
      other.userMetadata == userMetadata &&
      other.technicalMetadata == technicalMetadata;

  @override
  int get hashCode => Object.hash(location, text, userMetadata, technicalMetadata);
}
