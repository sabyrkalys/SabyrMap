import 'package:app/landmarks/import_export/export/export_options.dart';
import 'package:app/landmarks/import_export/export/export_options_schema.dart';
import 'package:app/landmarks/import_export/export/export_request.dart';
import 'package:app/landmarks/import_export/export/export_result.dart';
import 'package:app/landmarks/import_export/registry/format_capability.dart';
import 'package:app/landmarks/import_export/registry/format_descriptor.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:app/landmarks/services/landmark_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/landmark_services_provider.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../sheet_menu.dart';
import 'ldk_context_actions.dart';

/// «Экспортировать как...»: формат → его параметры → папка → экспорт →
/// итог с путём. Сам экспорт — [ExportService].
abstract final class LdkExportFlow {
  static const String unsupported = 'Формат не поддерживает содержимое файла';

  /// Объекты файла для экспорта. Файл меток пока не хранит вложенных
  /// объектов — у него пусто; у файла другого типа — он сам.
  static List<LandmarkObject> objectsOf(LandmarkFile file) =>
      switch (file.content) {
        LdkFileObject() => const [],
        final object => [object],
      };

  /// Запускает экспорт файла [path]; результат — итог или null (отмена,
  /// нечего экспортировать).
  static Future<ExportResult?> start(BuildContext context, String path) async {
    final services = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(landmarkServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));

    final LandmarkFile file;
    try {
      file = await services.repository.load(path);
    } on Exception catch (e) {
      say('Не удалось прочитать файл: $e');
      return null;
    }
    if (!context.mounted) return null;

    final format = await pickFormat(context, services.formatRegistry.exporters);
    if (format == null || !context.mounted) return null;
    final objects = [
      for (final o in objectsOf(file))
        if (format.supports(FormatCapability.exportOf(o.type))) o,
    ];
    if (objects.isEmpty) {
      say(unsupported);
      return null;
    }

    final defaults = await services.exportService.defaultOptions(format);
    if (!context.mounted) return null;
    final options = await ExportOptionsSheet.show(context, format, defaults);
    if (options == null || !context.mounted) return null;

    final root = services.paths.landmarks;
    final folder = await FolderPickerDialog.show(
      context,
      folders: services.folders,
      root: root,
      initial: p.dirname(path),
    );
    if (folder == null || !context.mounted) return null;

    final result = await services.exportService.export(
      ExportRequest(
        objects: objects,
        format: format,
        options: options,
        targetFolder: folder,
        preferredFilename: objects.length == 1
            ? null
            : LdkContextActions.displayName(file, path),
      ),
    );
    await services.explorerController.refresh();
    if (!context.mounted) return result;
    if (!result.success) {
      say(result.errorMessage ?? 'Экспорт не удался');
      return result;
    }
    await _showResult(context, services, result.filePath!);
    return result;
  }

  /// Шаг 1: выбор формата из [formats].
  static Future<FormatDescriptor?> pickFormat(
    BuildContext context,
    List<FormatDescriptor> formats,
  ) => showModalBottomSheet<FormatDescriptor>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SheetMenu(
      key: const Key('ldk_export_formats'),
      title: 'Экспортировать как...',
      children: [
        for (final format in formats)
          InkWell(
            key: Key('ldk_export_format_${format.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(context, format),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 32,
                    child: Icon(
                      Icons.file_present,
                      size: 24,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          format.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            color: SheetMenuColors.text,
                          ),
                        ),
                        Text(
                          format.extensions.join(', '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: SheetMenuColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        SheetMenuCancel(
          buttonKey: const Key('ldk_export_cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  static Future<void> _showResult(
    BuildContext context,
    LandmarkServices services,
    String filePath,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('ldk_export_result'),
        title: const Text('Экспорт завершён'),
        content: SelectableText(filePath),
        actions: [
          TextButton(
            key: const Key('ldk_export_share'),
            onPressed: () async {
              Navigator.pop(dialog);
              final text = await LdkContextActions.share(services, filePath);
              if (text != null) {
                messenger.showSnackBar(SnackBar(content: Text(text)));
              }
            },
            child: const Text('ПОДЕЛИТЬСЯ'),
          ),
          TextButton(
            key: const Key('ldk_export_open'),
            onPressed: () async {
              Navigator.pop(dialog);
              await services.explorerController.openFolder(p.dirname(filePath));
            },
            child: const Text('ОТКРЫТЬ'),
          ),
          TextButton(
            key: const Key('ldk_export_ok'),
            onPressed: () => Navigator.pop(dialog),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }
}

/// Шаг 2: параметры формата по его схеме. Без параметров шаг пропускается.
class ExportOptionsSheet extends StatefulWidget {
  const ExportOptionsSheet({
    super.key,
    required this.format,
    required this.defaults,
  });

  final FormatDescriptor format;
  final ExportOptions defaults;

  /// Опции или null («ОТМЕНА»).
  static Future<ExportOptions?> show(
    BuildContext context,
    FormatDescriptor format,
    ExportOptions defaults,
  ) async {
    final fields = format.exportAdapter?.optionsSchema.fields ?? const [];
    if (fields.isEmpty) return defaults;
    return showModalBottomSheet<ExportOptions>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportOptionsSheet(format: format, defaults: defaults),
    );
  }

  @override
  State<ExportOptionsSheet> createState() => _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends State<ExportOptionsSheet> {
  late final Map<String, Object?> _values = {
    ...widget.defaults.extras,
    'includeWaypoints': widget.defaults.includeWaypoints,
    'includeSegments': widget.defaults.includeSegments,
  };

  ExportOptions _result() => widget.defaults.copyWith(
    includeWaypoints: _values['includeWaypoints'] as bool? ?? true,
    includeSegments: _values['includeSegments'] as bool? ?? true,
    extras: Map.unmodifiable(_values),
  );

  Widget _field(ExportOptionField field) {
    final key = Key('ldk_export_option_${field.id}');
    switch (field.type) {
      case OptionFieldType.boolean:
        return SwitchListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          value: _values[field.id] as bool? ?? false,
          activeThumbColor: SheetMenuColors.accent,
          onChanged: (v) => setState(() => _values[field.id] = v),
        );
      case OptionFieldType.enumeration:
        final current = _values[field.id] as String?;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DropdownButtonFormField<String>(
            key: key,
            initialValue: field.values.contains(current) ? current : null,
            decoration: InputDecoration(labelText: field.label),
            items: [
              for (final v in field.values)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) => setState(() => _values[field.id] = v),
          ),
        );
      case OptionFieldType.string:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextFormField(
            key: key,
            initialValue: _values[field.id] as String? ?? '',
            decoration: InputDecoration(labelText: field.label),
            onChanged: (v) => _values[field.id] = v,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields =
        widget.format.exportAdapter?.optionsSchema.fields ??
        const <ExportOptionField>[];
    return SheetMenu(
      key: const Key('ldk_export_options'),
      title: widget.format.displayName,
      children: [
        for (final field in fields) _field(field),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('ldk_export_options_cancel'),
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: SheetMenuColors.accent,
                ),
                child: const Text(
                  'ОТМЕНА',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              TextButton(
                key: const Key('ldk_export_options_next'),
                onPressed: () => Navigator.pop(context, _result()),
                style: TextButton.styleFrom(
                  foregroundColor: SheetMenuColors.accent,
                ),
                child: const Text(
                  'ДАЛЕЕ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
