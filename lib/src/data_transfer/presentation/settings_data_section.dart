import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/components/option_row.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_icon.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../application/graph_composition.dart';
import '../application/graph_composition_provider.dart';
import '../application/graph_export_provider.dart';
import 'export_data_sheet.dart';

/// Раздел «Данные» страницы «Настройки»: пояснение, что граф хранится только
/// на устройстве, и строки операций с данными.
final class SettingsDataSection extends StatelessWidget {
  const SettingsDataSection({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок и пояснение выровнены по значкам строк.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  localizations.dataSectionTitle,
                  style: DoableType.section.copyWith(color: colors.ink),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                localizations.dataSectionLocalOnly,
                style: DoableType.hint.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const _ExportRow(),
      ],
    );
  }
}

/// Строка «Экспорт данных» открывает панель экспорта. Пустой граф
/// экспортировать нельзя, а пока экспорт идёт, строка показывает его ход и
/// не принимает выбор.
final class _ExportRow extends ConsumerWidget {
  const _ExportRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    OptionRow row({
      required String hint,
      VoidCallback? onPressed,
      OptionRowProgress? progress,
    }) => OptionRow(
      icon: DoableIconData.export,
      name: localizations.dataExportTitle,
      hint: hint,
      onPressed: onPressed,
      progress: progress,
    );
    return switch ((
      ref.watch(graphExportControllerProvider),
      ref.watch(graphCompositionProvider).value,
    )) {
      (GraphExportRunning(:final progress), _) => row(
        hint: localizations.dataExportRunning,
        progress: OptionRowProgress(
          share: progress,
          label: localizations.dataExportProgress(progress),
        ),
      ),
      // Пока состав не прочитан, неизвестно, есть ли что экспортировать.
      (GraphExportIdle(), null) => row(hint: localizations.dataExportHint),
      (GraphExportIdle(), GraphCompositionReadSucceeded(:final composition))
          when composition.isEmpty =>
        row(hint: localizations.dataExportNothing),
      // Отказ чтения состава не означает пустого графа.
      (
        GraphExportIdle(),
        GraphCompositionReadSucceeded() || GraphCompositionReadFailed(),
      ) =>
        row(
          hint: localizations.dataExportHint,
          onPressed: () => showExportDataSheet(context),
        ),
    };
  }
}
