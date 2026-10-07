import 'package:flutter/material.dart';

/// A group header (chevron, title, subtitle) whose [children] slide open
/// below it. Each accordion opens on its own; others are left as they are.
class MapSourceAccordion extends StatelessWidget {
  const MapSourceAccordion({
    super.key,
    required this.id,
    required this.title,
    this.subtitle,
    required this.isOpen,
    required this.onToggle,
    required this.children,
  });

  final String id;
  final String title;
  final String? subtitle;
  final bool isOpen;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('group_header_$id'),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}
