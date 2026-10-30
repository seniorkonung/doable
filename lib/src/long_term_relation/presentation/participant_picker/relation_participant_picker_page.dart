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
import '../../application/relation_pair_probe.dart';
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

  /// Оба состояния участников допускает только изменение архивной связи.
  static SelectRelationParticipant _purposeFor(
    RelationParticipantChoice choice,
  ) => SelectRelationParticipant(
    session: IntentionSearchSession(),
    pairProbe: _pairProbeFor(choice),
    selectionContext: switch (choice.flow) {
      RelationChangeChoiceFlow(relationScope: RelationScope.archived) =>
        RelationParticipantSelectionContext.archivedRelation,
      RelationCreationChoiceFlow() ||
      RelationChangeChoiceFlow(
        relationScope: RelationScope.active,
      ) => RelationParticipantSelectionContext.activeRelation,
    },
  );

  /// Проба есть, пока участник другой роли выбран.
  static RelationPairProbe? _pairProbeFor(RelationParticipantChoice choice) {
    final counterpart = switch (choice.role) {
      RelationParticipantRole.source => choice.related,
      RelationParticipantRole.related => choice.source,
    };
    if (counterpart == null) {
      return null;
    }
    return RelationPairProbe(
      counterpartId: counterpart.id,
      candidateRole: choice.role,
      ignoredRelationId: switch (choice.flow) {
        RelationCreationChoiceFlow() => null,
        RelationChangeChoiceFlow(:final relationId) => relationId,
      },
    );
  }

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
