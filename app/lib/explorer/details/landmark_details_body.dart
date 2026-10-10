import 'package:flutter/material.dart';

import '../descriptors/detail_data.dart';
import '../descriptors/landmark_type_descriptor.dart';
import 'landmark_details_section.dart';

/// Шапка дескриптора (если есть) и секции детализации.
class LandmarkDetailsBody extends StatelessWidget {
  const LandmarkDetailsBody({super.key, required this.descriptor, required this.data, required this.onMore});

  final LandmarkTypeDescriptor descriptor;
  final LandmarkDetailsData data;

  /// ⋮ у заголовка секции.
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final header = descriptor.buildDetailsHeader?.call(context, data);
    return SingleChildScrollView(
      key: const Key('details_body'),
      padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?header,
          for (final section in descriptor.buildDetailsSections(context, data))
            LandmarkDetailsSection(
              key: ValueKey('${data.item.path}:${section.title}'),
              section: section,
              data: data,
              onMore: onMore,
            ),
        ],
      ),
    );
  }
}
