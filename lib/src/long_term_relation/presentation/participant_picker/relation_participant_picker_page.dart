import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import 'relation_participant_choice.dart';
import 'relation_participant_picker_purpose.dart';

/// Выбор существующего намерения участником долговременной связи.
///
/// Страница показывает экран выбора над отдельной сессией ограниченного
/// каталога, ограничения которого выводит из описания выбора. Второе
/// намерение пары исключает запрос каталога по идентификатору, поэтому
/// одноимённые намерения остаются отдельными строками. Выбор возвращает
/// снимок участника с ревизией выдачи, из которой выбрана строка. Закрытие
/// не возвращает ничего и не создаёт намерений. Подзаголовок шапки
/// напоминает связь, из формы которой открыт поиск.
@RoutePage()
final class RelationParticipantPickerPage extends StatefulWidget {
  const RelationParticipantPickerPage({required this.choice, super.key});

  final RelationParticipantChoice choice;

  @override
  State<RelationParticipantPickerPage> createState() =>
      _RelationParticipantPickerPageState();
}

final class _RelationParticipantPickerPageState
    extends State<RelationParticipantPickerPage> {
  late final _purpose = _purposeFor(widget.choice);

  /// Исключает участника другой роли, пока он выбран. Оба состояния
  /// участников допускает только изменение архивной связи.
  static SelectRelationParticipant _purposeFor(
    RelationParticipantChoice choice,
  ) => SelectRelationParticipant(
    session: IntentionSearchSession(),
    excludedIntentionId: switch (choice.role) {
      RelationParticipantRole.source => choice.related?.id,
      RelationParticipantRole.related => choice.source?.id,
    },
    selectionContext: switch (choice.flow) {
      RelationChangeChoiceFlow(relationScope: RelationScope.archived) =>
        RelationParticipantSelectionContext.archivedRelation,
      RelationCreationChoiceFlow() ||
      RelationChangeChoiceFlow(
        relationScope: RelationScope.active,
      ) => RelationParticipantSelectionContext.activeRelation,
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IntentionPickerView(
      purpose: _purpose,
      purposeDescription: relationParticipantPickerPurpose(l10n, widget.choice),
      closeLabel: l10n.participantPickerCancel,
      emptyScopeMessage: l10n.participantPickerEmpty,
      onClose: () => unawaited(context.router.maybePop()),
      onPick: (pick) => unawaited(
        context.router.maybePop(
          GraphSnapshot(
            revision: pick.revision,
            value: RelationParticipantSummary(
              id: pick.value.id,
              title: pick.value.title,
              archiveState: pick.value.archiveState,
            ),
          ),
        ),
      ),
      onOpenDetails: (id) => unawaited(
        context.router.push(IntentionDetailsRoute(intentionId: id)),
      ),
    );
  }
}
