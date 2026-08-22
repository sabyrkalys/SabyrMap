import 'package:flutter/material.dart';

class TrackNameFormResult {
  const TrackNameFormResult({required this.name});

  final String name;
}

Future<TrackNameFormResult?> showTrackNameFormSheet(BuildContext context, {required String initialName}) {
  return showModalBottomSheet<TrackNameFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => TrackNameFormSheet(initialName: initialName),
  );
}

class TrackNameFormSheet extends StatefulWidget {
  const TrackNameFormSheet({super.key, required this.initialName});

  final String initialName;

  @override
  State<TrackNameFormSheet> createState() => _TrackNameFormSheetState();
}

class _TrackNameFormSheetState extends State<TrackNameFormSheet> {
  late final TextEditingController _nameController = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Сохранить трек', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('track_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('track_save_button'),
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                      TrackNameFormResult(name: _nameController.text.trim()),
                    ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
