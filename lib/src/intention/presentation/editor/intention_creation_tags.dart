import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/tag_dot.dart';
import '../../../tag/application/tag_read_result.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/presentation/tag_color_presentation.dart';
import 'intention_editor_state.dart';

/// Выбранные теги черновика создания намерения.
///
/// Показывает проекцию сессии компактными элементами в её порядке: с
/// последними известными названием и цветом, состоянием наблюдения и
/// доступным снятием. Снятие и повтор наблюдения передаются
/// владельцу через [onRemove] и [onRetryObservation] и меняют только черновик
/// и его проекцию: виджет назначений не записывает и тегов не читает. Пустой
/// набор места не занимает.
final class IntentionCreationTags extends StatelessWidget {
  const IntentionCreationTags({
    required this.tags,
    required this.enabled,
    required this.onRemove,
    required this.onRetryObservation,
    super.key,
  });

  /// Проекция выбранных тегов сессии в ручном порядке.
  final Map<TagId, IntentionDraftTag> tags;

  /// Черновик принимает правки: во время отправки и после завершения сессии
  /// снятие недоступно.
  final bool enabled;
  final ValueChanged<TagId> onRemove;

  /// Повторяет наблюдение тега после устранимого отказа чтения.
  final ValueChanged<TagId> onRetryObservation;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    // Снятие тега не считается нажатием вне поля ввода: ввод продолжается с
    // прежним фокусом.
    return TextFieldTapRegion(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final MapEntry(key: id, value: tag) in tags.entries)
            _DraftTagChip(
              id: id,
              name: tag.name.value,
              color: tagColorPresentation(tag.color),
              status: tag.status,
              onRemove: enabled ? () => onRemove(id) : null,
              onRetryObservation: () => onRetryObservation(id),
            ),
        ],
      ),
    );
  }
}

/// Компактный элемент выбранного тега: название, состояние и снятие из
/// черновика.
///
/// Состояние отличается не только цветом: проверка — значком, отказ чтения —
/// значком и текстом причины. Экранный диктор получает название вместе с состоянием;
/// повтор проверки предлагается только при устранимом отказе чтения.
final class _DraftTagChip extends StatelessWidget {
  const _DraftTagChip({
    required this.id,
    required this.name,
    required this.color,
    required this.status,
    required this.onRemove,
    required this.onRetryObservation,
  });

  final TagId id;
  final String name;
  final DoableTagColor? color;
  final IntentionDraftTagStatus status;
  final VoidCallback? onRemove;
  final VoidCallback onRetryObservation;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final key = id.toCanonicalString();
    final (Widget? marker, _DraftTagReadProblem? problem) = switch (status) {
      IntentionDraftTagAvailable() => (null, null),
      IntentionDraftTagLoading() => (
        Icon(
          Icons.hourglass_empty,
          key: ValueKey('intention-editor-tag-loading-$key'),
          size: 16,
          semanticLabel: localizations.editorDraftTagChecking,
        ),
        null,
      ),
      IntentionDraftTagReadFailed(:final failure, :final canRetry) => (
        null,
        _DraftTagReadProblem(
          _readFailureMessage(localizations, failure),
          canRetry: canRetry,
        ),
      ),
    };
    return Semantics(
      container: true,
      child: Material(
        key: ValueKey('intention-editor-tag-$key'),
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: problem == null ? colors.outline : colors.error,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Длинное название и состояние переносятся, а не обрезаются.
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 0, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TagDot(color: color, size: TagDotSize.medium),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            name,
                            key: ValueKey('intention-editor-tag-name-$key'),
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        if (marker != null) ...[
                          const SizedBox(width: 4),
                          marker,
                        ],
                      ],
                    ),
                    if (problem != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sync_problem,
                            size: 16,
                            color: colors.error,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              problem.message,
                              key: ValueKey('intention-editor-tag-status-$key'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (problem case _DraftTagReadProblem(canRetry: true))
              IconButton(
                key: ValueKey('intention-editor-tag-retry-$key'),
                tooltip: localizations.editorRetryDraftTag(name),
                onPressed: onRetryObservation,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            IconButton(
              key: ValueKey('intention-editor-tag-remove-$key'),
              tooltip: localizations.editorRemoveDraftTag(name),
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// Отказ чтения выбранного тега для показа.
final class _DraftTagReadProblem {
  const _DraftTagReadProblem(this.message, {required this.canRetry});

  final String message;

  /// Повтор наблюдения разрешён контрактом сессии.
  final bool canRetry;
}

/// Отказ чтения называет свою причину и не выдаётся за удаление тега.
String _readFailureMessage(
  AppLocalizations localizations,
  TagReadFailure failure,
) => switch (failure) {
  TagReadUnavailableFailure() => localizations.editorDraftTagReadUnavailable,
  TagReadCorruptionFailure() => localizations.editorDraftTagReadCorruption,
  TagReadUnexpectedFailure() => localizations.editorDraftTagReadUnexpected,
};
