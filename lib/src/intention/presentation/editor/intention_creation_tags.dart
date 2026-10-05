import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../tag/application/tag_read_result.dart';
import '../../../tag/domain/tag_id.dart';
import 'intention_editor_state.dart';

/// Выбранные теги черновика создания намерения.
///
/// Показывает проекцию сессии компактными элементами в порядке набора: с
/// последним известным названием, состоянием наблюдения и доступным снятием.
/// Тег, отсутствие которого подтвердил отказ создания, показывается
/// удалённым независимо от проекции. Снятие и повтор наблюдения передаются
/// владельцу через [onRemove] и [onRetryObservation] и меняют только черновик
/// и его проекцию: виджет назначений не записывает и тегов не читает. Пустой
/// набор места не занимает.
final class IntentionCreationTags extends StatelessWidget {
  const IntentionCreationTags({
    required this.tags,
    required this.missingTagIds,
    required this.enabled,
    required this.onRemove,
    required this.onRetryObservation,
    super.key,
  });

  /// Проекция выбранных тегов сессии с ключами и порядком набора черновика.
  final Map<TagId, IntentionDraftTag> tags;

  /// Выбранные теги, отсутствие которых подтвердил последний отказ создания.
  final Set<TagId> missingTagIds;

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
              // Отказ создания подтвердил отсутствие в транзакции: это
              // сильнее ещё не обновлённой проекции.
              status: missingTagIds.contains(id)
                  ? const IntentionDraftTagMissing()
                  : tag.status,
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
/// Состояние отличается не только цветом: проверка — значком, удаление —
/// зачёркнутым названием, значком и текстом, отказ чтения — значком и
/// текстом причины. Экранный диктор получает название вместе с состоянием;
/// повтор проверки предлагается только при устранимом отказе чтения.
final class _DraftTagChip extends StatelessWidget {
  const _DraftTagChip({
    required this.id,
    required this.name,
    required this.status,
    required this.onRemove,
    required this.onRetryObservation,
  });

  final TagId id;
  final String name;
  final IntentionDraftTagStatus status;
  final VoidCallback? onRemove;
  final VoidCallback onRetryObservation;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final key = id.toCanonicalString();
    final (Widget? marker, _DraftTagProblem? problem) = switch (status) {
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
      IntentionDraftTagMissing() => (
        null,
        _DraftTagProblem.missing(localizations.editorDraftTagMissing),
      ),
      IntentionDraftTagReadFailed(:final failure, :final canRetry) => (
        null,
        _DraftTagProblem.readFailed(
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
                        Flexible(
                          child: Text(
                            name,
                            key: ValueKey('intention-editor-tag-name-$key'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              decoration: (problem?.isMissing ?? false)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
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
                          Icon(problem.icon, size: 16, color: colors.error),
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
            if (problem case _DraftTagProblem(canRetry: true))
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

/// Недоступность выбранного тега для показа: подтверждённое отсутствие или
/// отказ чтения.
final class _DraftTagProblem {
  /// Отсутствие окончательно: удалённый тег не возвращается с прежним
  /// идентификатором, поэтому повтор не предлагается.
  const _DraftTagProblem.missing(this.message)
    : icon = Icons.label_off_outlined,
      isMissing = true,
      canRetry = false;

  const _DraftTagProblem.readFailed(this.message, {required this.canRetry})
    : icon = Icons.sync_problem,
      isMissing = false;

  final IconData icon;
  final String message;
  final bool isMissing;

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
