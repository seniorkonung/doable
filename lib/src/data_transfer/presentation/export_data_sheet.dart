import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/components/caution.dart';
import '../../design_system/components/sheet.dart';
import '../../design_system/doable_icon.dart';
import '../../design_system/doable_metrics.dart';
import '../application/graph_composition.dart';
import '../application/graph_composition_provider.dart';
import '../application/graph_export_provider.dart';

/// Открывает над страницей и её панелью навигации панель «Экспорт данных»
/// с составом будущего файла и предупреждением, что файл не защищён.
///
/// «Сохранить в файл» закрывает панель и запускает экспорт, который
/// продолжается независимо от открытых страниц. Закрытие панели без выбора
/// ничего не меняет.
Future<void> showExportDataSheet(BuildContext context) => showDoableSheet<void>(
  context: context,
  builder: (_) => const _ExportDataSheet(),
);

final class _ExportDataSheet extends ConsumerWidget {
  const _ExportDataSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    // Отказ чтения не означает пустого графа, поэтому панель показывает
    // предупреждение и кнопку без состава.
    final composition = switch (ref.watch(graphCompositionProvider).value) {
      GraphCompositionReadSucceeded(:final composition) =>
        localizations.dataExportComposition(
          composition.intentionCount,
          composition.relationCount,
          composition.dailyChoiceCount,
          composition.tagCount,
        ),
      GraphCompositionReadFailed() || null => null,
    };
    return Sheet(
      title: localizations.dataExportTitle,
      text: composition,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Caution(
              icon: DoableIconData.lockOpen,
              message: localizations.dataExportUnprotected,
            ),
            const SizedBox(height: DoableMetrics.space3),
            FilledButton(
              onPressed: () {
                final export = ref.read(graphExportControllerProvider.notifier);
                Navigator.of(context).pop();
                unawaited(export.start());
              },
              child: Text(localizations.dataExportSave),
            ),
          ],
        ),
      ),
    );
  }
}
