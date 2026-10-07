import 'package:flutter/material.dart';

import 'available_maps_models.dart';
import 'storage_bar.dart';

/// Left panel sliding over the screen body. Closes on a tap on the dimmed
/// area or a swipe to the left.
class SideDrawer extends StatelessWidget {
  const SideDrawer({
    super.key,
    required this.isOpen,
    required this.activeSection,
    required this.storage,
    required this.folders,
    required this.onSectionSelected,
    required this.onClose,
  });

  final bool isOpen;
  final MapsSection activeSection;
  final StorageUsage? storage;
  final List<DeviceFolder> folders;
  final ValueChanged<MapsSection> onSectionSelected;
  final VoidCallback onClose;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.8).clamp(0.0, 320.0);
    return Stack(
      children: [
        IgnorePointer(
          ignoring: !isOpen,
          child: AnimatedOpacity(
            opacity: isOpen ? 1 : 0,
            duration: _duration,
            child: GestureDetector(
              key: const Key('side_drawer_scrim'),
              onTap: onClose,
              child: const ColoredBox(color: Color(0x66000000), child: SizedBox.expand()),
            ),
          ),
        ),
        AnimatedSlide(
          offset: isOpen ? Offset.zero : const Offset(-1, 0),
          duration: _duration,
          curve: Curves.easeOut,
          child: ExcludeSemantics(
            excluding: !isOpen,
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -200) onClose();
              },
              child: Material(
                key: const Key('side_drawer'),
                elevation: 8,
                color: theme.colorScheme.surface,
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      const _Header('ОНЛАЙН-КАРТЫ'),
                      for (final section in MapsSection.values)
                        ListTile(
                          key: Key('drawer_section_${section.name}'),
                          title: Text(section.label),
                          selected: section == activeSection,
                          onTap: () => onSectionSelected(section),
                        ),
                      const Divider(),
                      const _Header('КАРТЫ НА УСТРОЙСТВЕ'),
                      StorageBar(usage: storage, showPath: true),
                      for (final folder in folders)
                        ListTile(
                          key: Key('drawer_folder_${folder.name}'),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: Text(folder.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                          // Stub until the device file browser is wired in.
                          onTap: () => debugPrint('Open folder: ${folder.path}'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
