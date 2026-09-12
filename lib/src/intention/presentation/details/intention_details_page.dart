import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import 'intention_details_state.dart';
import 'intention_details_view_model.dart';

@RoutePage()
final class IntentionDetailsPage extends ConsumerWidget {
  const IntentionDetailsPage({required this.intentionId, super.key});

  final IntentionId intentionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = intentionDetailsViewModelProvider(intentionId);
    final details = ref.watch(provider);
    ref.listen(provider, (previous, next) {
      if (next is IntentionDetailsDeleted) {
        unawaited(context.router.maybePop());
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(localizations.detailsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            if (details.isOperationRunning) const _RunningOperationStatus(),
            Expanded(
              child: _DetailsContent(intentionId: intentionId, state: details),
            ),
          ],
        ),
      ),
    );
  }
}

final class _RunningOperationStatus extends StatelessWidget {
  const _RunningOperationStatus();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(localizations.detailsOperationRunning)),
          ],
        ),
      ),
    );
  }
}

final class _DetailsContent extends ConsumerWidget {
  const _DetailsContent({required this.intentionId, required this.state});

  final IntentionId intentionId;
  final IntentionDetailsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionDetailsLoading() => _DetailsStatus(
        message: localizations.detailsLoading,
        progressIndicator: true,
      ),
      IntentionDetailsLoaded(:final intention) => _LoadedDetails(
        intention: intention,
      ),
      IntentionDetailsNotFound() => _DetailsStatus(
        message: localizations.detailsNotFound,
      ),
      IntentionDetailsUnavailable() => _DetailsStatus(
        message: localizations.detailsUnavailable,
        retryLabel: localizations.commonRetry,
        onRetry: ref
            .read(intentionDetailsViewModelProvider(intentionId).notifier)
            .retry,
      ),
      IntentionDetailsCorruption() => _DetailsStatus(
        message: localizations.detailsCorruption,
      ),
      IntentionDetailsUnexpected() => _DetailsStatus(
        message: localizations.detailsUnexpected,
      ),
      IntentionDetailsDeleted() => _DetailsStatus(
        message: localizations.detailsNotFound,
      ),
    };
  }
}

final class _LoadedDetails extends StatelessWidget {
  const _LoadedDetails({required this.intention});

  final Intention intention;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final readiness = switch (intention.readiness) {
      IntentionReadiness.ready => localizations.catalogReady,
      IntentionReadiness.notReady => localizations.catalogNotReady,
    };
    final archiveState = switch (intention.archiveState) {
      IntentionArchiveState.active => localizations.detailsActive,
      IntentionArchiveState.archived => localizations.detailsArchived,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          header: true,
          child: Text(
            intention.title,
            key: const ValueKey('intention-details-title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 24),
        _DetailsField(
          label: localizations.detailsDescriptionLabel,
          value: intention.description ?? localizations.detailsNoDescription,
        ),
        const SizedBox(height: 16),
        _DetailsField(
          label: localizations.detailsReadinessLabel,
          value: readiness,
        ),
        const SizedBox(height: 16),
        _DetailsField(
          label: localizations.detailsArchiveStateLabel,
          value: archiveState,
        ),
      ],
    );
  }
}

final class _DetailsField extends StatelessWidget {
  const _DetailsField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}

final class _DetailsStatus extends StatelessWidget {
  const _DetailsStatus({
    required this.message,
    this.progressIndicator = false,
    this.retryLabel,
    this.onRetry,
  }) : assert((retryLabel == null) == (onRetry == null));

  final String message;
  final bool progressIndicator;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progressIndicator) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              Text(message, textAlign: TextAlign.center),
              if (onRetry case final retry?) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: retry, child: Text(retryLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
