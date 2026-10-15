import 'dart:typed_data';

import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/models/landmark_header.dart';

import 'binary_reader.dart';
import 'binary_writer.dart';
import 'location_codec.dart';
import 'metadata_codec.dart';

/// Запись и чтение файла метки целиком.
///
/// ```text
/// Header:
///   int magicWithVersion      — (magic << 8) | version, см. LandmarkHeader
///   int headerSize            — размер заголовка в байтах (sabyrmap пишет 8)
/// Body:
///   Metadata technical
///   Metadata user
///   payload:
///     waypoint → Location
///     set      → Waypoints
///     route    → Waypoints
///     area     → AreaPolygons
///     track    → Waypoints, TrackSegments
///     ldkFile  → пусто или Objects
///     circle   → Location center + double radiusMeters
///     text     → Location + String text
///
/// Waypoints     = int count + Waypoint * count
/// Waypoint      = Metadata user + Location
/// AreaPolygons  = int count + AreaPolygon * count
/// AreaPolygon   = Metadata user + Locations outline + int holeCount + Locations * holeCount
/// TrackSegments = int count + TrackSegment * count
/// TrackSegment  = Metadata user + Locations
/// Locations     = int count + Location * count
/// Objects       = int count + (int byteLength + файл метки целиком) * count
/// ```
///
/// Decision: `headerSize` включает оба поля заголовка. Если он больше 8,
/// лишние байты пропускаются: так новые версии смогут дописать поля в
/// заголовок, не ломая чтение. Устройство AreaPolygon и TrackSegment
/// (метаданные + списки точек) выбрано по аналогии с Waypoint.
/// Байты после payload считаются повреждением файла. Вложенный объект
/// файла меток — обычный файл метки со своим заголовком (так его тип и
/// версия читаются тем же кодом); пустой payload — файл без объектов
/// (файлы, записанные до вложенных объектов).
abstract final class LandmarkCodec {
  /// Файл в байты.
  static Uint8List encode(LandmarkFile file) {
    if (file.type != file.content.type) {
      throw SerializationException('File type ${file.type.name} does not match content type ${file.content.type.name}');
    }
    final header = LandmarkHeader(type: file.type);
    final w = BinaryWriter()
      ..writeInt(header.magicWithVersion)
      ..writeInt(header.headerSize);
    MetadataCodec.write(w, file.content.technicalMetadata);
    MetadataCodec.write(w, file.content.userMetadata);

    switch (file.content) {
      case WaypointObject o:
        LocationCodec.write(w, o.location);
      case SetObject o:
        _writeWaypoints(w, o.waypoints);
      case RouteObject o:
        _writeWaypoints(w, o.waypoints);
      case AreaObject o:
        w.writeInt(o.polygons.length);
        for (final polygon in o.polygons) {
          MetadataCodec.write(w, polygon.userMetadata);
          LocationCodec.writeList(w, polygon.outline);
          w.writeInt(polygon.holes.length);
          for (final hole in polygon.holes) {
            LocationCodec.writeList(w, hole);
          }
        }
      case TrackObject o:
        _writeWaypoints(w, o.waypoints);
        w.writeInt(o.segments.length);
        for (final segment in o.segments) {
          MetadataCodec.write(w, segment.userMetadata);
          LocationCodec.writeList(w, segment.locations);
        }
      case CircleObject o:
        LocationCodec.write(w, o.center);
        w.writeDouble(o.radiusMeters);
      case TextObject o:
        LocationCodec.write(w, o.location);
        w.writeString(o.text);
      case LdkFileObject o:
        if (o.objects.isNotEmpty) _writeObjects(w, o.objects);
      default:
        throw SerializationException('Unsupported landmark object ${file.content.runtimeType}');
    }
    return w.toBytes();
  }

  /// Байты в файл. Повреждённые и обрезанные данные — [SerializationException].
  static LandmarkFile decode(Uint8List bytes) {
    final r = BinaryReader(bytes);
    final header = readHeader(r);

    final technical = MetadataCodec.read(r);
    final user = MetadataCodec.read(r);
    final LandmarkObject content = switch (header.type) {
      LandmarkType.waypoint => WaypointObject(
        location: LocationCodec.read(r),
        userMetadata: user,
        technicalMetadata: technical,
      ),
      LandmarkType.set => SetObject(waypoints: _readWaypoints(r), userMetadata: user, technicalMetadata: technical),
      LandmarkType.route => RouteObject(waypoints: _readWaypoints(r), userMetadata: user, technicalMetadata: technical),
      LandmarkType.area => AreaObject(polygons: _readPolygons(r), userMetadata: user, technicalMetadata: technical),
      LandmarkType.track => TrackObject(
        waypoints: _readWaypoints(r),
        segments: _readSegments(r),
        userMetadata: user,
        technicalMetadata: technical,
      ),
      LandmarkType.circle => CircleObject(
        center: LocationCodec.read(r),
        radiusMeters: _readRadius(r),
        userMetadata: user,
        technicalMetadata: technical,
      ),
      LandmarkType.text => TextObject(
        location: LocationCodec.read(r),
        text: r.readString(),
        userMetadata: user,
        technicalMetadata: technical,
      ),
      LandmarkType.ldkFile => LdkFileObject(
        userMetadata: user,
        technicalMetadata: technical,
        objects: r.remaining == 0 ? const [] : _readObjects(r),
      ),
    };
    if (r.remaining != 0) {
      throw SerializationException('${r.remaining} unexpected trailing byte(s)', position: r.position);
    }
    return LandmarkFile(type: header.type, content: content);
  }

  /// Читает и проверяет заголовок; [r] остаётся сразу за ним.
  static LandmarkHeader readHeader(BinaryReader r) {
    final packed = r.readInt();
    final magic = LandmarkHeader.magicOf(packed);
    final type = LandmarkType.fromMagic(magic);
    if (type == null) {
      throw SerializationException('Unknown file signature 0x${magic.toRadixString(16)}', position: 0);
    }
    final version = LandmarkHeader.versionOf(packed);
    if (version != LandmarkType.formatVersion) {
      throw SerializationException('Unsupported ${type.extension} format version $version', position: 0);
    }
    final sizeAt = r.position;
    final headerSize = r.readInt();
    if (headerSize < LandmarkHeader.byteSize) {
      throw SerializationException('Invalid header size $headerSize', position: sizeAt);
    }
    r.skip(headerSize - LandmarkHeader.byteSize);
    return LandmarkHeader(type: type, version: version, headerSize: headerSize);
  }

  static double _readRadius(BinaryReader r) {
    final at = r.position;
    final radius = r.readDouble();
    if (!radius.isFinite || radius <= 0) throw SerializationException('Invalid circle radius $radius', position: at);
    return radius;
  }

  static void _writeObjects(BinaryWriter w, List<LandmarkObject> objects) {
    w.writeInt(objects.length);
    for (final object in objects) {
      if (object is LdkFileObject) {
        throw const SerializationException('A landmark file cannot contain another landmark file');
      }
      final bytes = encode(LandmarkFile(type: object.type, content: object));
      w.writeInt(bytes.length);
      w.writeBytes(bytes);
    }
  }

  static List<LandmarkObject> _readObjects(BinaryReader r) {
    final count = LocationCodec.readCount(r, 'object');
    final objects = <LandmarkObject>[];
    for (var i = 0; i < count; i++) {
      final at = r.position;
      final file = decode(r.readBytes(LocationCodec.readCount(r, 'object byte')));
      if (file.type == LandmarkType.ldkFile) {
        throw SerializationException('Nested landmark file', position: at);
      }
      objects.add(file.content);
    }
    return objects;
  }

  static void _writeWaypoints(BinaryWriter w, List<WaypointObject> waypoints) {
    w.writeInt(waypoints.length);
    for (final waypoint in waypoints) {
      MetadataCodec.write(w, waypoint.userMetadata);
      LocationCodec.write(w, waypoint.location);
    }
  }

  static List<WaypointObject> _readWaypoints(BinaryReader r) {
    final count = LocationCodec.readCount(r, 'waypoint');
    return [
      for (var i = 0; i < count; i++)
        WaypointObject(userMetadata: MetadataCodec.read(r), location: LocationCodec.read(r)),
    ];
  }

  static List<AreaPolygon> _readPolygons(BinaryReader r) {
    final count = LocationCodec.readCount(r, 'polygon');
    return [
      for (var i = 0; i < count; i++)
        AreaPolygon(
          userMetadata: MetadataCodec.read(r),
          outline: LocationCodec.readList(r),
          holes: [for (var h = LocationCodec.readCount(r, 'hole'); h > 0; h--) LocationCodec.readList(r)],
        ),
    ];
  }

  static List<TrackSegment> _readSegments(BinaryReader r) {
    final count = LocationCodec.readCount(r, 'segment');
    return [
      for (var i = 0; i < count; i++)
        TrackSegment(userMetadata: MetadataCodec.read(r), locations: LocationCodec.readList(r)),
    ];
  }
}
