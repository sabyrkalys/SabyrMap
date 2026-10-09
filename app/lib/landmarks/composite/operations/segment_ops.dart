import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/models/landmark_track.dart';

/// Правка сегментов трека. Чистые функции: возвращают новый список
/// сегментов; неверный индекс — [RangeError], недопустимая операция —
/// [ArgumentError].
abstract final class SegmentOps {
  /// Добавляет точку в сегмент [segmentIndex] на место [atIndex] (по
  /// умолчанию — в конец). Decision: у трека без сегментов индекс 0
  /// создаёт первый сегмент.
  static List<TrackSegment> addLocation(
    List<TrackSegment> segments,
    int segmentIndex,
    LandmarkLocation location, {
    int? atIndex,
  }) {
    if (segments.isEmpty && segmentIndex == 0 && (atIndex ?? 0) == 0) {
      return [TrackSegment(locations: [location])];
    }
    RangeError.checkValidIndex(segmentIndex, segments, 'segmentIndex');
    final segment = segments[segmentIndex];
    final index = atIndex ?? segment.locations.length;
    RangeError.checkValueInInterval(index, 0, segment.locations.length, 'atIndex');
    return _replace(segments, segmentIndex, _with(segment, [...segment.locations]..insert(index, location)));
  }

  static List<TrackSegment> removeLocation(List<TrackSegment> segments, int segmentIndex, int locationIndex) {
    final segment = _segment(segments, segmentIndex);
    RangeError.checkValidIndex(locationIndex, segment.locations, 'locationIndex');
    return _replace(segments, segmentIndex, _with(segment, [...segment.locations]..removeAt(locationIndex)));
  }

  static List<TrackSegment> moveLocation(
    List<TrackSegment> segments,
    int segmentIndex,
    int locationIndex,
    LandmarkLocation newLocation,
  ) {
    final segment = _segment(segments, segmentIndex);
    RangeError.checkValidIndex(locationIndex, segment.locations, 'locationIndex');
    return _replace(segments, segmentIndex, _with(segment, [...segment.locations]..[locationIndex] = newLocation));
  }

  /// Делит сегмент: точка [locationIndex] становится первой во втором
  /// сегменте. Оба получают метаданные исходного. [locationIndex] = 0 или
  /// за последней точкой — [ArgumentError] (пустой сегмент).
  static List<TrackSegment> splitSegment(List<TrackSegment> segments, int segmentIndex, int locationIndex) {
    final segment = _segment(segments, segmentIndex);
    if (locationIndex <= 0 || locationIndex >= segment.locations.length) {
      throw ArgumentError.value(locationIndex, 'locationIndex', 'must split into two non-empty segments');
    }
    final first = _with(segment, segment.locations.sublist(0, locationIndex));
    final second = _with(segment, segment.locations.sublist(locationIndex));
    return [...segments]..replaceRange(segmentIndex, segmentIndex + 1, [first, second]);
  }

  static List<TrackSegment> deleteSegment(List<TrackSegment> segments, int segmentIndex) {
    RangeError.checkValidIndex(segmentIndex, segments, 'segmentIndex');
    return [...segments]..removeAt(segmentIndex);
  }

  /// Точки [second] дописываются в конец [first], [second] удаляется.
  static List<TrackSegment> mergeSegments(List<TrackSegment> segments, int first, int second) {
    RangeError.checkValidIndex(first, segments, 'first');
    RangeError.checkValidIndex(second, segments, 'second');
    if (first == second) throw ArgumentError.value(second, 'second', 'must differ from first');
    final merged = _with(segments[first], [...segments[first].locations, ...segments[second].locations]);
    final out = [...segments]..[first] = merged;
    return out..removeAt(second);
  }

  /// Все точки в одном сегменте с метаданными первого; без сегментов — пусто.
  static List<TrackSegment> groupAll(List<TrackSegment> segments) {
    if (segments.isEmpty) return const [];
    return [
      _with(segments.first, [for (final s in segments) ...s.locations]),
    ];
  }

  static TrackSegment _segment(List<TrackSegment> segments, int index) {
    RangeError.checkValidIndex(index, segments, 'segmentIndex');
    return segments[index];
  }

  static TrackSegment _with(TrackSegment s, List<LandmarkLocation> locations) =>
      TrackSegment(userMetadata: s.userMetadata, locations: locations);

  static List<TrackSegment> _replace(List<TrackSegment> segments, int index, TrackSegment segment) =>
      [...segments]..[index] = segment;
}
