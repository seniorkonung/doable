import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../tag/domain/tag_id.dart';
import 'intention_editor_state.dart';

/// Выбранные теги черновика создания намерения.
///
/// Показывает проекцию сессии компактными элементами в порядке набора: с
/// последним известным названием и доступным снятием. Снятие передаётся
/// владельцу через [onRemove] и меняет только черновик: назначений не
/// записывает и тегов не читает. Пустой набор места не занимает.
final class IntentionCreationTags extends StatelessWidget {
  const IntentionCreationTags({
    required this.tags,
    required this.enabled,
    required this.onRemove,
    super.key,
  });

  /// Проекция выбранных тегов сессии с ключами и порядком набора черновика.
  final Map<TagId, IntentionDraftTag> tags;

  /// Черновик принимает правки: во время отправки и после завершения сессии
  /// снятие недоступно.
  final bool enabled;
  final ValueChanged<TagId> onRemove;

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
              tag: tag,
              onRemove: enabled ? () => onRemove(id) : null,
            ),
        ],
      ),
    );
  }
}

/// Компактный элемент выбранного тега: название и снятие из черновика.
final class _DraftTagChip extends StatelessWidget {
  const _DraftTagChip({
    required this.id,
    required this.tag,
    required this.onRemove,
  });

  final TagId id;
  final IntentionDraftTag tag;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final key = id.toCanonicalString();
    final name = tag.name.value;
    return Semantics(
      container: true,
      child: Material(
        key: ValueKey('intention-editor-tag-$key'),
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Длинное название переносится, а не обрезается.
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 0, 8),
                child: Text(name, style: theme.textTheme.labelLarge),
              ),
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
