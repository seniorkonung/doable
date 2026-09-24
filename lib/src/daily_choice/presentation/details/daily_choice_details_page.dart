import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/daily_choice_id.dart';
import '../daily_choice_command_failure_message.dart';
import '../editor/daily_choice_path_replacement_flow.dart';
import 'daily_choice_delete_confirmation.dart';
import 'daily_choice_details_state.dart';
import 'daily_choice_details_view_model.dart';

@RoutePage()
final class DailyChoiceDetailsPage extends ConsumerStatefulWidget {
  const DailyChoiceDetailsPage({required this.choiceId, super.key});

  final DailyChoiceId choiceId;

  @override
  ConsumerState<DailyChoiceDetailsPage> createState() =>
      _DailyChoiceDetailsPageState();
}

final class _DailyChoiceDetailsPageState
    extends ConsumerState<DailyChoiceDetailsPage> {
  late DailyChoiceDetailsViewModel _model;
  late GraphCommandCoordinator _coordinator;
  DailyChoiceOperationToken? _activeDeleteToken;
  DailyChoiceOperationToken? _failureToken;
  GraphInitiatorPresentationClaim? _failureClaim;
  DailyChoiceCommandFailure? _deleteFailure;
  bool _confirmationOpen = false;
  bool _deleting = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    _model = DailyChoiceDetailsViewModel(
      ref.read(personalGraphRepositoryProvider),
      widget.choiceId,
    );
  }

  @override
  void didUpdateWidget(covariant DailyChoiceDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choiceId != widget.choiceId) {
      _releasePresentation();
      _activeDeleteToken = null;
      _confirmationOpen = false;
      _deleting = false;
      _deleted = false;
      _deleteFailure = null;
      _model.dispose();
      _model = DailyChoiceDetailsViewModel(
        ref.read(personalGraphRepositoryProvider),
        widget.choiceId,
      );
    }
  }

  @override
  void dispose() {
    _releasePresentation();
    _model.dispose();
    super.dispose();
  }

  void _releasePresentation() {
    final active = _activeDeleteToken;
    if (active != null) _coordinator.releaseInitiatorPresentation(active);
    final failed = _failureToken;
    if (failed != null) _coordinator.releaseInitiatorPresentation(failed);
    _failureToken = null;
    _failureClaim = null;
  }

  Future<void> _confirmDelete(DailyChoiceDetails details) async {
    if (_confirmationOpen || _deleting || _deleted) return;
    setState(() => _confirmationOpen = true);
    final confirmed = await confirmDailyChoiceDeletion(context, details);
    if (!mounted) return;
    setState(() => _confirmationOpen = false);
    if (!confirmed ||
        widget.choiceId != details.choice.id ||
        _model.state is! DailyChoiceDetailsLoaded) {
      return;
    }
    _startDelete();
  }

  void _startDelete() {
    if (_deleting || _deleted) return;
    _releasePresentation();
    final start = _coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(widget.choiceId),
    );
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        setState(() {
          _activeDeleteToken = token;
          _deleteFailure = null;
          _deleting = true;
        });
        unawaited(_finishDelete(token, future));
      case DailyChoiceCommandAlreadyRunning():
        setState(
          () => _deleteFailure = const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.dependencyChanged,
          ),
        );
      case GraphCommandCoordinatorDraining():
        setState(() => _deleteFailure = const DailyChoiceUnexpectedFailure());
    }
  }

  Future<void> _finishDelete(
    DailyChoiceOperationToken token,
    Future<DailyChoiceCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      if (!mounted || !identical(_activeDeleteToken, token)) return;
      _activeDeleteToken = null;
      switch (completion.result) {
        case GraphResultSuccess(value: DailyChoiceDeleted(:final choice))
            when choice.id == widget.choiceId:
          setState(() {
            _deleting = false;
            _deleted = true;
          });
          if (ModalRoute.of(context)?.isCurrent ?? false) {
            unawaited(Navigator.of(context).maybePop());
          }
        case GraphResultFailure(:final failure):
          final canPresentHere = ModalRoute.of(context)?.isCurrent ?? false;
          if (!canPresentHere) {
            _coordinator.releaseInitiatorPresentation(token);
          }
          setState(() {
            _deleting = false;
            _deleteFailure = failure;
            _failureToken = canPresentHere ? token : null;
            _failureClaim = canPresentHere
                ? _coordinator.claimInitiatorFailure(token)
                : null;
          });
        case GraphResultSuccess():
          setState(() {
            _deleting = false;
            _deleteFailure = const DailyChoiceUnexpectedFailure();
          });
      }
    } on Object {
      if (!mounted || !identical(_activeDeleteToken, token)) return;
      _coordinator.releaseInitiatorPresentation(token);
      setState(() {
        _activeDeleteToken = null;
        _deleting = false;
        _deleteFailure = const DailyChoiceUnexpectedFailure();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(l10n.dailyChoiceDetailsTitle),
          actions: [
            if (_model.state case DailyChoiceDetailsLoaded(:final details)
                when !_deleted && !_deleting && !_confirmationOpen)
              IconButton(
                key: const ValueKey('daily-choice-edit-open'),
                tooltip: l10n.dailyChoiceEditTitle,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(
                  context.router.push(DailyChoiceEditRoute(details: details)),
                ),
              ),
            if (_model.state case DailyChoiceDetailsLoaded()
                when !_deleted && !_deleting && !_confirmationOpen)
              IconButton(
                key: const ValueKey('daily-choice-replace-open'),
                tooltip: l10n.dailyChoiceReplaceOpen,
                icon: const Icon(Icons.alt_route),
                onPressed: () => unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => DailyChoicePathReplacementFlow(
                        choiceId: widget.choiceId,
                      ),
                    ),
                  ),
                ),
              ),
            if (_model.state case DailyChoiceDetailsLoaded(:final details)
                when !_deleted)
              IconButton(
                key: const ValueKey('daily-choice-delete-open'),
                tooltip: l10n.dailyChoiceDeleteAction,
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleting || _confirmationOpen
                    ? null
                    : () => unawaited(_confirmDelete(details)),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_deleting) const LinearProgressIndicator(),
              if (_deleteFailure case final failure?)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OperationFailurePresentation(
                    claim: _failureClaim,
                    message: dailyChoiceCommandFailureMessage(l10n, failure),
                    messageKey: const ValueKey('daily-choice-delete-failure'),
                  ),
                ),
              Expanded(
                child: _deleted
                    ? _Status(l10n.dailyChoiceDetailsNotFound)
                    : switch (_model.state) {
                        DailyChoiceDetailsLoading() => _Status(
                          l10n.dailyChoiceDetailsLoading,
                          isLoading: true,
                        ),
                        DailyChoiceDetailsNotFound() => _Status(
                          l10n.dailyChoiceDetailsNotFound,
                        ),
                        DailyChoiceDetailsUnavailable() => _Status(
                          l10n.dailyChoiceDetailsUnavailable,
                          onRetry: _model.retry,
                        ),
                        DailyChoiceDetailsCorruption() => _Status(
                          l10n.dailyChoiceDetailsCorruption,
                        ),
                        DailyChoiceDetailsUnexpected() => _Status(
                          l10n.dailyChoiceDetailsUnexpected,
                        ),
                        DailyChoiceDetailsLoaded(:final details) =>
                          details.path.isEmpty
                              ? _Status(l10n.dailyChoiceDetailsCorruption)
                              : _ChoicePath(details: details),
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Status extends StatelessWidget {
  const _Status(this.message, {this.isLoading = false, this.onRetry});

  final String message;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading) const CircularProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
        ],
      ),
    ),
  );
}

final class _ChoicePath extends StatelessWidget {
  const _ChoicePath({required this.details});

  final DailyChoiceDetails details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = details.path;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 3 + path.length * 2,
      itemBuilder: (context, index) {
        if (index == 0) return _Summary(details: details);
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                l10n.dailyChoiceDetailsPath,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          );
        }
        if (index == 2) {
          return _Participant(
            intention: details.source,
            role: l10n.dailyChoiceDetailsSource,
            position: 1,
          );
        }
        final stepIndex = (index - 3) ~/ 2;
        final step = path[stepIndex];
        if (index.isOdd) {
          return _Relation(step: step, position: stepIndex + 1);
        }
        return _Participant(
          intention: step.related,
          role: stepIndex == path.length - 1
              ? l10n.dailyChoiceDetailsSelectedAction
              : l10n.dailyChoiceDetailsIntermediate,
          position: stepIndex + 2,
          showReadiness: stepIndex == path.length - 1,
        );
      },
    );
  }
}

final class _Summary extends StatelessWidget {
  const _Summary({required this.details});

  final DailyChoiceDetails details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final choice = details.choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.dailyChoiceDetailsPhrase(
              details.source.title,
              details.selected.title,
            ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.dailyChoiceDetailsDate(choice.date.toCanonicalString())),
        Text(
          choice.isCompleted
              ? l10n.dailyChoiceDetailsCompleted
              : l10n.dailyChoiceDetailsNotCompleted,
        ),
        if (choice.description != null) ...[
          const SizedBox(height: 8),
          Text(l10n.dailyChoiceDetailsDescription),
          Text(choice.description!.value),
        ],
      ],
    );
  }
}

final class _Participant extends StatelessWidget {
  const _Participant({
    required this.intention,
    required this.role,
    required this.position,
    this.showReadiness = false,
  });

  final Intention intention;
  final String role;
  final int position;
  final bool showReadiness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = intention.archiveState == IntentionArchiveState.archived
        ? l10n.dailyChoiceDetailsArchived
        : l10n.dailyChoiceDetailsActive;
    final readiness = intention.readiness == IntentionReadiness.ready
        ? l10n.dailyChoiceDetailsReady
        : l10n.dailyChoiceDetailsNotReady;
    final subtitle = showReadiness ? '$state · $readiness' : state;
    void onOpen() => unawaited(
      context.router.push(IntentionDetailsRoute(intentionId: intention.id)),
    );
    return Semantics(
      key: ValueKey('daily-choice-intention-$position'),
      button: true,
      label: '$role, ${intention.title}, $subtitle',
      onTap: onOpen,
      child: ExcludeSemantics(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('$role: ${intention.title}'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      ),
    );
  }
}

final class _Relation extends StatelessWidget {
  const _Relation({required this.step, required this.position});

  final DailyChoicePathStepDetails step;
  final int position;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final relation = step.relation;
    final type = relation.type == LongTermRelationType.need
        ? l10n.relationNeighborhoodTypeNeed
        : l10n.relationNeighborhoodTypeCan;
    final phrase = relation.type == LongTermRelationType.need
        ? l10n.relationNeighborhoodNeedPhrase(
            step.source.title,
            step.related.title,
          )
        : l10n.relationNeighborhoodCanPhrase(
            step.source.title,
            step.related.title,
          );
    final scope = relation.scope == RelationScope.archived
        ? l10n.dailyChoiceDetailsArchived
        : l10n.dailyChoiceDetailsActive;
    final priority = 'P${relation.priority.index + 1}';
    final summary = '${l10n.relationDetailsPriorityLabel}: $priority · $scope';
    final subtitle = step.description == null
        ? summary
        : '$summary\n${step.description!.value}';
    void onOpen() => unawaited(
      context.router.push(RelationDetailsRoute(relationId: relation.id)),
    );
    return Semantics(
      key: ValueKey('daily-choice-relation-$position'),
      button: true,
      label:
          '${l10n.dailyChoiceDetailsStep(position)}, $type, $phrase, $subtitle',
      onTap: onOpen,
      child: ExcludeSemantics(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('$type: $phrase'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      ),
    );
  }
}
