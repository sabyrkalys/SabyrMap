import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format_track_stats.dart';
import 'track_detail_screen.dart';
import 'tracks_controller.dart';

class TracksListScreen extends ConsumerStatefulWidget {
  const TracksListScreen({super.key});

  @override
  ConsumerState<TracksListScreen> createState() => _TracksListScreenState();
}

class _TracksListScreenState extends ConsumerState<TracksListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(tracksControllerProvider.notifier).loadTracks());
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Треки')),
      body: tracks.isEmpty
          ? const Center(child: Text('Пока нет сохранённых треков'))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    key: Key('track_card_${track.id}'),
                    title: Text(track.name, style: const TextStyle(fontSize: 18)),
                    subtitle: Text(
                      '${formatTrackDate(track.createdAt)} · ${formatTrackLength(track.lengthMeters)} · '
                      '${formatTrackDuration(track.durationSeconds)}',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TrackDetailScreen(track: track)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
