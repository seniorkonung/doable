import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/picker/intention_picker_row.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_pair_probe.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_participant_choice.dart';
import 'relation_participant_picker_purpose.dart';

/// Выбор существующего намерения участником долговременной связи.
///
/// Страница показывает экран выбора над отдельной сессией ограниченного
/// каталога, ограничения которого выводит из описания выбора. Второе
/// намерение пары исключает запрос каталога по идентификатору, поэтому
/// одноимённые намерения остаются отдельными строками. Строки, выбор которых
/// дал бы занятую пару, отмечены и не выбираются. Нажатие на их текст открывает
/// занимающую связь поверх поиска, а при создании архивную связь предлагает
/// восстановить с подтверждением. Пока форма создания не может продолжаться,
/// например пока выполняется восстановление, нажатия на текст строк ничего не
/// делают. Выбор возвращает снимок участника с ревизией выдачи, из которой
/// выбрана строка. Закрытие не возвращает ничего и не создаёт намерений.
/// Подзаголовок шапки напоминает связь, из формы которой открыт поиск.
@RoutePage()
final class RelationParticipantPickerPage extends ConsumerStatefulWidget {
  const RelationParticipantPickerPage({required this.choice, super.key});

  final RelationParticipantChoice choice;

  @override
  ConsumerState<RelationParticipantPickerPage> createState() =>
      _RelationParticipantPickerPageState();
}

final class _RelationParticipantPickerPageState
    extends ConsumerState<RelationParticipantPickerPage> {
  late final _purpose = _purposeFor(widget.choice);

  /// Восстановление уже предложено: от нажатия до ответа на подтверждение.
  bool _offeringRestore = false;

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

  /// Может ли поток формы продолжаться. Дескриптора у изменения связи нет:
  /// оно продолжается всегда.
  bool get _canContinue => switch (widget.choice.flow) {
    RelationCreationChoiceFlow(:final restore) => restore.canContinue,
    RelationChangeChoiceFlow() => true,
  };

  bool get _ownsTopRoute =>
      mounted &&
      context.router.stackData.lastOrNull?.matchId ==
          context.routeData.matchId &&
      !context.router.hasPagelessTopRoute;

  void _openRelation(LongTermRelationId id) =>
      unawaited(context.router.push(RelationDetailsRoute(relationId: id)));

  /// Что значит занятая пара в этом потоке: предложение восстановить архивную
  /// связь есть только при создании.
  OccupiedPairMark _occupiedPairMark(PairOccupant occupant) {
    void open() {
      if (_canContinue) _openRelation(occupant.relationId);
    }

    return switch ((widget.choice.flow, occupant.scope)) {
      (final RelationCreationChoiceFlow flow, RelationScope.archived) =>
        OccupiedPairMark(
          kind: OccupiedPairKind.restorable,
          onTap: () => unawaited(_offerRestore(occupant.relationId, flow)),
        ),
      (_, RelationScope.active) => OccupiedPairMark(
        kind: OccupiedPairKind.linked,
        onTap: open,
      ),
      (_, RelationScope.archived) => OccupiedPairMark(
        kind: OccupiedPairKind.archived,
        onTap: open,
      ),
    };
  }

  /// Спрашивает, восстановить ли связь [id], и передаёт согласие форме.
  ///
  /// Подтверждению нужны данные связи, а строка выдачи их не несёт. Если чтение
  /// их не дало, сообщения об этом показывает подробный просмотр связи: своей
  /// поверхности сообщений у поиска нет.
  Future<void> _offerRestore(
    LongTermRelationId id,
    RelationCreationChoiceFlow flow,
  ) async {
    final restore = flow.restore;
    if (_offeringRestore || !restore.canContinue) return;
    _offeringRestore = true;
    try {
      final read = await ref
          .read(personalGraphRepositoryProvider)
          .watchRelation(id)
          .first;
      // Пока шло чтение, поиск могли закрыть или перекрыть.
      if (!_ownsTopRoute) return;
      if (read case LongTermRelationReadSuccess(
        value: GraphSnapshot(value: final details?),
      )) {
        if (await _confirmRestore(details, flow)) restore.accept(id);
      } else {
        _openRelation(id);
      }
    } finally {
      _offeringRestore = false;
    }
  }

  /// Данные черновика, которые восстановление не перенесёт в связь, одной
  /// строкой; `null`, если отличий нет.
  ///
  /// Отличием считается только заданное в форме: невыбранные вид и приоритет и
  /// пустое описание ничего не теряют. Отличающийся вид называется словами.
  String? _discardedDraftWarning(
    AppLocalizations l10n,
    LongTermRelationDetails details,
    RelationCreationChoiceFlow flow,
  ) {
    final type = widget.choice.type;
    final priority = flow.priority;
    final description = flow.description;
    final discarded = [
      if (type != null && type != details.relation.type)
        switch (type) {
          LongTermRelationType.need =>
            l10n.participantPickerRestoreWarningNeedType,
          LongTermRelationType.can =>
            l10n.participantPickerRestoreWarningCanType,
        },
      if (priority != null && priority != details.relation.priority)
        l10n.participantPickerRestoreWarningPriority,
      if (description.trim().isNotEmpty &&
          description != details.description?.value)
        l10n.participantPickerRestoreWarningDescription,
    ];
    if (discarded.isEmpty) return null;
    return l10n.participantPickerRestoreWarning(discarded.join(', '));
  }

  Future<bool> _confirmRestore(
    LongTermRelationDetails details,
    RelationCreationChoiceFlow flow,
  ) {
    final l10n = AppLocalizations.of(context);
    return showPreservingConfirmDialog(
      context: context,
      title: l10n.participantPickerRestoreTitle,
      text: ConfirmDialogText(
        before: l10n.participantPickerRestoreTextBefore,
        name: switch (details.relation.type) {
          LongTermRelationType.need => l10n.relationNeighborhoodNeedPhrase(
            details.source.title,
            details.related.title,
          ),
          LongTermRelationType.can => l10n.relationNeighborhoodCanPhrase(
            details.source.title,
            details.related.title,
          ),
        },
        after: l10n.participantPickerRestoreTextAfter(
          details.relation.priority.name.toUpperCase(),
        ),
      ),
      warning: _discardedDraftWarning(l10n, details, flow),
      cancelLabel: l10n.participantPickerRestoreCancel,
      actionLabel: l10n.participantPickerRestoreConfirm,
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
      onPick: (pick) {
        if (!_canContinue) return;
        unawaited(
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
        );
      },
      onOpenDetails: (id) => unawaited(
        context.router.push(IntentionDetailsRoute(intentionId: id)),
      ),
      occupiedPairMark: _occupiedPairMark,
    );
  }
}
