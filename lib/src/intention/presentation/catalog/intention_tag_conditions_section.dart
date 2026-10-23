import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/tag_dot.dart';
import '../../../tag/presentation/panel/tags_panel.dart';
import '../../../tag/presentation/panel/tags_panel_context.dart';
import '../../../tag/presentation/tag_phrase_text.dart';
import 'intention_catalog_purpose.dart';
import 'intention_tag_conditions_view_model.dart';

/// Раздел выбранных условий по тегам одного назначения поиска.
///
/// Условия показаны чипами в порядке добавления с переносом на новые строки.
/// Нажатие на чип переключает надобность, крестик снимает условие, кнопка
/// «+ Тег» открывает панель тегов в режиме фильтра над условиями этого
/// поиска: изменения в ней сразу применяются к выдаче, а закрытие условий не
/// меняет. Раздел не читает граф и не выполняет команд тегов.
final class IntentionTagConditionsSection extends ConsumerWidget {
  const IntentionTagConditionsSection({required this.purpose, super.key});

  final IntentionCatalogPurpose purpose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = intentionTagConditionsViewModelProvider(purpose);
    final conditions = ref.watch(provider).conditions;
    final model = ref.read(provider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final condition in conditions)
          _ConditionChip(
            condition: condition,
            onToggle: () => model.toggleRequirement(condition.tagId),
            onRemove: () => model.remove(condition.tagId),
          ),
        OutlinedButton.icon(
          key: const ValueKey('intention-tag-conditions-add'),
          onPressed: () =>
              unawaited(showTagsPanel(context, TagsPanelFilterContext(model))),
          icon: const Icon(Icons.add),
          label: Text(
            localizations.intentionTagConditionsAdd,
            semanticsLabel: localizations.intentionTagConditionsAddSemantics,
          ),
        ),
      ],
    );
  }
}

/// Чип условия: надобность передана значком и текстом, а не только цветом.
final class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.condition,
    required this.onToggle,
    required this.onRemove,
  });

  final IntentionTagCondition condition;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final id = condition.tagId.toCanonicalString();
    final name = condition.name.value;
    final (icon, semanticsLabel) = switch (condition.requirement) {
      IntentionTagRequirement.mustBePresent => (
        Icons.check,
        localizations.intentionTagConditionPresentSemantics(name),
      ),
      IntentionTagRequirement.mustBeAbsent => (
        Icons.block,
        localizations.intentionTagConditionAbsentSemantics(name),
      ),
    };
    return Material(
      key: ValueKey('intention-tag-condition-$id'),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              container: true,
              button: true,
              label: semanticsLabel,
              hint: localizations.intentionTagConditionToggleHint,
              onTap: onToggle,
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('intention-tag-condition-toggle-$id'),
                onTap: onToggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 8),
                        // Длинное название переносится, а не обрезается.
                        Flexible(
                          child: tagPhraseText(
                            phrase: (name) => switch (condition.requirement) {
                              IntentionTagRequirement.mustBePresent => name,
                              IntentionTagRequirement.mustBeAbsent =>
                                localizations.intentionTagConditionAbsent(name),
                            },
                            tags: [(name: name, color: condition.color)],
                            dotSize: TagDotSize.medium,
                            key: const ValueKey(
                              'intention-tag-condition-label',
                            ),
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('intention-tag-condition-remove-$id'),
            tooltip: localizations.intentionTagConditionRemove(name),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
