import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'compass_source.dart';

/// Cardinal/intercardinal label for a heading in degrees [0, 360).
String cardinalLabel(double heading) {
  const labels = ['С', 'СВ', 'В', 'ЮВ', 'Ю', 'ЮЗ', 'З', 'СЗ'];
  final index = (((heading % 360) + 22.5) / 45).floor() % 8;
  return labels[index];
}

class CompassScreen extends ConsumerStatefulWidget {
  const CompassScreen({super.key});

  @override
  ConsumerState<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends ConsumerState<CompassScreen> {
  StreamSubscription<double?>? _subscription;
  double? _heading;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    try {
      final stream = ref.read(compassSourceProvider).headingStream;
      if (stream == null) {
        _unavailable = true;
        return;
      }
      _subscription = stream.listen(
        (heading) {
          if (mounted) setState(() => _heading = heading);
        },
        onError: (_) {
          if (mounted) setState(() => _unavailable = true);
        },
      );
    } catch (_) {
      _unavailable = true;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heading = _heading;
    return Scaffold(
      appBar: AppBar(title: const Text('Компас')),
      body: Center(
        child: _unavailable
            ? const Text('Компас недоступен на этом устройстве')
            : heading == null
                ? const CircularProgressIndicator(key: Key('compass_loading'))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: Transform.rotate(
                          angle: -heading * (math.pi / 180),
                          child: Icon(
                            Icons.navigation,
                            key: const Key('compass_needle'),
                            size: 240,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '${heading.round()}° ${cardinalLabel(heading)}',
                        key: const Key('compass_heading_text'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
      ),
    );
  }
}
