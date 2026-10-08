import 'package:flutter/material.dart';

import '../../icons/icon_library_scanner.dart';
import 'icon_category_section.dart';
import 'marker_icon.dart';

/// Opens the «Иконка» sheet. Completes with the chosen icon, [noneOption]
/// for «Нет», or null on «ОТМЕНА». The user's own icon files (from
/// [scanner]) are the last category, «СВОИ ИКОНКИ».
Future<MarkerIcon?> showMarkerIconSheet(
  BuildContext context, {
  String? currentIconId,
  IconLibraryScanner? scanner,
  List<IconCategory> categories = sampleCategories,
}) {
  return showModalBottomSheet<MarkerIcon>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: IconPickerSheet.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) =>
        IconPickerSheet(currentIconId: currentIconId, scanner: scanner ?? IconLibraryScanner(), categories: categories),
  );
}

/// «Иконка»: «Нет», then the categories as accordions, any number open.
class IconPickerSheet extends StatefulWidget {
  const IconPickerSheet({super.key, this.currentIconId, this.scanner, this.categories = sampleCategories});

  static const Color background = Color(0xFFEEF1F5);

  final String? currentIconId;
  final IconLibraryScanner? scanner;
  final List<IconCategory> categories;

  @override
  State<IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<IconPickerSheet> {
  final Set<String> _expandedCategoryIds = {};
  List<MarkerIcon> _ownIcons = const [];

  static const ownCategoryId = 'own';

  @override
  void initState() {
    super.initState();
    _loadOwnIcons();
  }

  Future<void> _loadOwnIcons() async {
    final scanner = widget.scanner;
    if (scanner == null) return;
    try {
      final files = await scanner.scan();
      if (!mounted) return;
      setState(() {
        _ownIcons = [
          for (final file in files)
            MarkerIcon(
              id: '${MarkerIcon.filePrefix}${file.fileName}',
              label: file.displayName,
              assetPath: file.path,
              fileName: file.fileName,
            ),
        ];
      });
    } catch (_) {
      // No icon folder (tests, no storage): just the built-in categories.
    }
  }

  void _toggle(String id) => setState(() {
    if (!_expandedCategoryIds.remove(id)) _expandedCategoryIds.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final categories = [
      ...widget.categories,
      if (_ownIcons.isNotEmpty) IconCategory(id: ownCategoryId, title: 'СВОИ ИКОНКИ', icons: _ownIcons),
    ];
    // A fixed height: opening a category doesn't make the sheet grow and
    // move the header that was just tapped.
    return SizedBox(
      key: const Key('icon_picker_sheet'),
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Иконка',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('icon_picker_list'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        key: const Key('marker_icon_none'),
                        onTap: () => Navigator.of(context).pop(noneOption),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text('Нет', style: TextStyle(fontSize: 16, color: Color(0xFF212121))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final category in categories)
                        IconCategorySection(
                          category: category,
                          isExpanded: _expandedCategoryIds.contains(category.id),
                          onToggle: () => _toggle(category.id),
                          onSelected: (icon) => Navigator.of(context).pop(icon),
                          currentIconId: widget.currentIconId,
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('icon_picker_cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A38E)),
                  child: const Text('ОТМЕНА', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
