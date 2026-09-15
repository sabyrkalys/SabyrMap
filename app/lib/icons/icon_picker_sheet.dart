import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'icon_library_scanner.dart';

class IconPickResult {
  const IconPickResult.file(this.fileName);
  const IconPickResult.reset() : fileName = null;

  final String? fileName;
}

Future<IconPickResult?> showIconPickerSheet(BuildContext context, {IconLibraryScanner? scanner}) {
  return showModalBottomSheet<IconPickResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _IconPickerSheet(scanner: scanner ?? IconLibraryScanner()),
  );
}

class _IconPickerSheet extends StatefulWidget {
  const _IconPickerSheet({required this.scanner});

  final IconLibraryScanner scanner;

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet> {
  late final Future<List<IconFile>> _future = widget.scanner.scan();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: FutureBuilder<List<IconFile>>(
          future: _future,
          builder: (context, snapshot) {
            final files = snapshot.data ?? const <IconFile>[];
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
              itemCount: files.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Tile(
                    key: const Key('icon_picker_default_tile'),
                    label: 'Стандартная',
                    icon: const Icon(Icons.circle, size: 32),
                    onTap: () => Navigator.of(context).pop(const IconPickResult.reset()),
                  );
                }
                final file = files[index - 1];
                return _Tile(
                  key: Key('icon_picker_tile_${file.fileName}'),
                  label: file.displayName,
                  icon: file.format == IconFileFormat.svg
                      ? SvgPicture.file(
                          File(file.path),
                          width: 32,
                          height: 32,
                          placeholderBuilder: (_) => const Icon(Icons.image, size: 32),
                        )
                      : Image.file(File(file.path), width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                  onTap: () => Navigator.of(context).pop(IconPickResult.file(file.fileName)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [icon, const SizedBox(height: 4), Text(label, overflow: TextOverflow.ellipsis)],
      ),
    );
  }
}
