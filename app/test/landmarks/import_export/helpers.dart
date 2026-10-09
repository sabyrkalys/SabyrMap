import 'dart:convert';
import 'dart:typed_data';

import 'package:app/landmarks/models/landmark_location.dart';

Uint8List bytesOf(String text) => utf8.encode(text);

/// Точка; [ele] — метры, [t] — Unix ms.
LandmarkLocation loc(double lat, double lon, {double? ele, int? t}) => LandmarkLocation(
  latitude: lat,
  longitude: lon,
  values: [
    if (ele != null) LocationValue(type: LocationValueType.elevation, value: (ele * 1000).round()),
    if (t != null) LocationValue(type: LocationValueType.utcTime, value: t),
  ],
);

const String sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="50.4501" lon="30.5234">
    <ele>179.5</ele>
    <time>2026-10-09T08:30:00Z</time>
    <name>Bunker</name>
    <cmt>north entrance</cmt>
    <desc>concrete</desc>
    <sym>flag</sym>
  </wpt>
  <wpt lat="50.46" lon="30.53"><name>Post</name></wpt>
  <rte>
    <name>Route A</name>
    <rtept lat="50.0" lon="30.0"><name>Start</name></rtept>
    <rtept lat="50.1" lon="30.1"/>
  </rte>
  <trk>
    <name>Walk</name>
    <trkseg>
      <trkpt lat="50.0" lon="30.0"><ele>100</ele><time>2026-10-09T08:00:00Z</time></trkpt>
      <trkpt lat="50.001" lon="30.001"><ele>101</ele><time>2026-10-09T08:01:00Z</time></trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="50.01" lon="30.01"/>
    </trkseg>
  </trk>
</gpx>''';
