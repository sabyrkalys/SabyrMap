import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import 'format_track_stats.dart';
import 'track_models.dart';

class TrackDetailScreen extends StatefulWidget {
  const TrackDetailScreen({super.key, required this.track});

  final Track track;

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  MapLibreMapController? _controller;

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    final points = widget.track.points;
    if (controller == null || points.isEmpty) return;

    await controller.addLine(
      LineOptions(
        geometry: [for (final p in points) LatLng(p.lat, p.lng)],
        lineColor: '#1976D2',
        lineWidth: 3,
      ),
    );

    if (points.length < 2) return;
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        left: 32,
        top: 32,
        right: 32,
        bottom: 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final firstPoint = track.points.isEmpty ? null : track.points.first;
    return Scaffold(
      appBar: AppBar(title: Text(track.name)),
      body: Column(
        children: [
          Expanded(
            child: MapLibreMap(
              styleString: AppConfig.mapStyleUrl,
              initialCameraPosition: CameraPosition(
                target: firstPoint == null ? const LatLng(0, 0) : LatLng(firstPoint.lat, firstPoint.lng),
                zoom: 12,
              ),
              onMapCreated: (controller) => _controller = controller,
              onStyleLoadedCallback: _onStyleLoaded,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              key: const Key('track_stats_row'),
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Длина', value: formatTrackLength(track.lengthMeters)),
                _Stat(label: 'Время', value: formatTrackDuration(track.durationSeconds)),
                _Stat(label: 'Набор высоты', value: formatElevationGain(track.elevationGainMeters)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
