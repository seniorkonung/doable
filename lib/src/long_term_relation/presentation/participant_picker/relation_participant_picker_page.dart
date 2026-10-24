import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../../application/long_term_relation_projection.dart';

/// Выбор существующего намерения участником долговременной связи.
///
/// Страница показывает экран выбора над отдельной сессией ограниченного
/// каталога. Второе намерение пары исключает запрос каталога по
/// идентификатору, поэтому одноимённые намерения остаются отдельными
/// строками. Выбор возвращает снимок участника с ревизией выдачи, из которой
/// выбрана строка. Закрытие не возвращает ничего и не создаёт намерений.
@RoutePage()
final class RelationParticipantPickerPage extends StatefulWidget {
  const RelationParticipantPickerPage({
    required this.selectionContext,
    this.excludedIntentionId,
    super.key,
  });

  /// Намерение другой роли; пока она пуста, исключения нет.
  final IntentionId? excludedIntentionId;

  /// Архивное состояние редактируемой связи, выраженное допустимым охватом.
  final RelationParticipantSelectionContext selectionContext;

  @override
  State<RelationParticipantPickerPage> createState() =>
      _RelationParticipantPickerPageState();
}

final class _RelationParticipantPickerPageState
    extends State<RelationParticipantPickerPage> {
  late final _purpose = SelectRelationParticipant(
    session: IntentionSearchSession(),
    excludedIntentionId: widget.excludedIntentionId,
    selectionContext: widget.selectionContext,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IntentionPickerView(
      purpose: _purpose,
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
