import 'package:flutter/material.dart';

const Color _secondary = Color(0xFF757575);

/// Поле «метка — значение»: метка курсивом в колонке 130.
class LayerDetailsFieldRow extends StatelessWidget {
  const LayerDetailsFieldRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: _secondary)),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF212121)),
              ),
            ),
          ],
        ),
      );
}

/// Сворачиваемая секция: заголовок со стрелкой и поля.
class LayerDetailsSection extends StatefulWidget {
  const LayerDetailsSection({super.key, required this.title, required this.fields, this.initiallyExpanded = true});

  final String title;
  final List<LayerDetailsFieldRow> fields;
  final bool initiallyExpanded;

  @override
  State<LayerDetailsSection> createState() => _LayerDetailsSectionState();
}

class _LayerDetailsSectionState extends State<LayerDetailsSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: Key('details_section_${widget.title}'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 22, color: const Color(0xFF333333)),
                    const SizedBox(width: 8),
                    Text(
                      widget.title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: _secondary,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...widget.fields,
          ],
        ),
      );
}
