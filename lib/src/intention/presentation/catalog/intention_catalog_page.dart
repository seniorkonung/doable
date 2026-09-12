import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/intention_repository.dart';
import '../../domain/intention.dart';
import 'intention_catalog_state.dart';
import 'intention_catalog_view_model.dart';

@RoutePage()
final class IntentionCatalogPage extends ConsumerWidget {
  const IntentionCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final catalog = ref.watch(intentionCatalogViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: Text(localizations.navigationActiveIntentions)),
      body: catalog.when(
        data: (state) => _CatalogContent(state: state),
        error: (_, _) =>
            _CatalogStatus(message: localizations.catalogUnexpectedFailure),
        loading: () => _CatalogStatus(
          message: localizations.catalogLoading,
          progressIndicator: true,
        ),
      ),
    );
  }
}

final class _CatalogContent extends ConsumerWidget {
  const _CatalogContent({required this.state});

  final IntentionCatalogState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionCatalogLoaded loaded => _LoadedCatalog(state: loaded),
      IntentionCatalogEmpty empty => _CatalogStatus(
        message: _emptyMessage(localizations, empty.scope),
      ),
      IntentionCatalogUnavailable() => _CatalogStatus(
        message: localizations.catalogUnavailable,
        retryLabel: localizations.commonRetry,
        onRetry: () {
          ref.read(intentionCatalogViewModelProvider.notifier).retry();
        },
      ),
      IntentionCatalogCorruption() => _CatalogStatus(
        message: localizations.catalogCorruption,
      ),
      IntentionCatalogUnexpected() => _CatalogStatus(
        message: localizations.catalogUnexpectedFailure,
      ),
    };
  }

  String _emptyMessage(AppLocalizations localizations, IntentionScope scope) =>
      switch (scope) {
        IntentionScope.active => localizations.catalogActiveEmpty,
        IntentionScope.archived => localizations.catalogArchivedEmpty,
        IntentionScope.all => localizations.catalogAllEmpty,
      };
}

final class _LoadedCatalog extends StatelessWidget {
  const _LoadedCatalog({required this.state});

  final IntentionCatalogLoaded state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            localizations.catalogTotalCount(state.totalCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state.items.length,
            itemBuilder: (context, index) =>
                _IntentionSummaryTile(summary: state.items[index]),
          ),
        ),
      ],
    );
  }
}

final class _IntentionSummaryTile extends StatelessWidget {
  const _IntentionSummaryTile({required this.summary});

  final IntentionSummary summary;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final readiness = switch (summary.readiness) {
      IntentionReadiness.ready => localizations.catalogReady,
      IntentionReadiness.notReady => localizations.catalogNotReady,
    };
    final description = summary.hasDescription
        ? localizations.catalogHasDescription
        : localizations.catalogNoDescription;
    return ListTile(
      title: Text(summary.title),
      subtitle: Wrap(
        spacing: 12,
        children: [Text(readiness), Text(description)],
      ),
    );
  }
}

final class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({
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
