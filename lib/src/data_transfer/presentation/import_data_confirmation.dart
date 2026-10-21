import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/doable_colors.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../graph_format/graph_format_records.dart';

/// Открывает над страницей подтверждение «Импортировать эту копию?»: когда
/// сохранён файл с заголовком [header], сколько в нём намерений,
/// долговременных связей, дневных выборов и тегов, и что импорт заменит
/// весь граф.
///
/// Возвращает `true`, только если выбрано «Импортировать и заменить»;
/// «Отмена» и закрытие подтверждения иначе — `false`.
Future<bool> confirmGraphImport(
  BuildContext context, {
  required GraphFormatHeader header,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ImportDataConfirmation(header),
    ) ??
    false;

final class _ImportDataConfirmation extends StatelessWidget {
  const _ImportDataConfirmation(this.header);

  final GraphFormatHeader header;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final title = localizations.dataImportConfirmationTitle;
    // Дата сохранения по местному времени устройства с месяцем по правилам
    // локали: «3 октября 2026», «3 October 2026».
    final savedOn = DateFormat(
      'd MMMM y',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(header.writtenAt.toLocal());
    final counts = header.counts;
    return AlertDialog(
      semanticLabel: title,
      scrollable: true,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.dataImportConfirmationFacts(
              savedOn,
              counts.intentions,
              counts.longTermRelations,
              counts.dailyChoices,
              counts.tags,
            ),
            style: DoableType.body.copyWith(color: colors.muted),
          ),
          const SizedBox(height: DoableMetrics.space2),
          Text(
            localizations.dataReplacementReplacesEverything,
            style: DoableType.body.copyWith(color: colors.ink),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(localizations.dataReplacementConfirmationCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
          ),
          child: Text(localizations.dataImportConfirm),
        ),
      ],
    );
  }
}
