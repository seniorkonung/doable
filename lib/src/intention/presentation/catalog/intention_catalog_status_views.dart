import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_state.dart';
import 'intention_catalog_view_model.dart';

/// Состояние каталога намерений вместо его списка.
///
/// Загрузка, пустота и безопасные отказы различимы и текстом, и семантикой:
/// живая область сообщает об изменении экранному диктору, а повтор доступен
/// только для устранимого отказа.
final class IntentionCatalogStatusView extends StatelessWidget {
  const IntentionCatalogStatusView({
    required this.message,
    this.progressIndicator = false,
    this.retryLabel,
    this.onRetry,
    super.key,
  }) : assert(
         (retryLabel == null) == (onRetry == null),
         'Повтор требует и подписи, и обработчика.',
       );

  final String message;
  final bool progressIndicator;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
      ),
    );
  }
}

/// Состояние продолжения каталога в конце уже загруженной части.
final class IntentionCatalogInlineStatus extends StatelessWidget {
  const IntentionCatalogInlineStatus({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Действие требует и подписи, и обработчика.',
       );

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onAction case final action?) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Локализованное состояние подгрузки выбранного каталога.
///
/// Конец, ожидание, устранимый отказ и утративший силу cursor остаются
/// отдельными состояниями: восстановление не изображается повтором порции.
final class IntentionCatalogContinuationStatusView extends ConsumerWidget {
  const IntentionCatalogContinuationStatusView({
    required this.purpose,
    required this.continuation,
    super.key,
  });

  final IntentionCatalogPurpose purpose;
  final IntentionCatalogContinuationState continuation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(
      intentionCatalogViewModelProvider(purpose).notifier,
    );
    return switch (continuation) {
      IntentionCatalogContinuationIdle() => const SizedBox.shrink(),
      IntentionCatalogContinuationLoading() => IntentionCatalogInlineStatus(
        message: localizations.catalogLoadingMore,
      ),
      IntentionCatalogContinuationUnavailable() => IntentionCatalogInlineStatus(
        message: localizations.catalogLoadMoreUnavailable,
        actionLabel: localizations.commonRetry,
        onAction: notifier.retryNextPage,
      ),
      IntentionCatalogContinuationCorruption() => IntentionCatalogInlineStatus(
        message: localizations.catalogLoadMoreCorruption,
      ),
      IntentionCatalogContinuationUnexpected() => IntentionCatalogInlineStatus(
        message: localizations.catalogLoadMoreUnexpected,
      ),
      IntentionCatalogContinuationValidation() => IntentionCatalogInlineStatus(
        message: localizations.catalogLoadMoreValidation,
        actionLabel: localizations.catalogReload,
        onAction: notifier.recoverFromInvalidCursor,
      ),
      IntentionCatalogContinuationRecovering() => IntentionCatalogInlineStatus(
        message: localizations.catalogReloading,
      ),
      IntentionCatalogRecoveryUnavailable() => IntentionCatalogInlineStatus(
        message: localizations.catalogUnavailable,
        actionLabel: localizations.commonRetry,
        onAction: notifier.retryRecovery,
      ),
      IntentionCatalogRecoveryCorruption() => IntentionCatalogInlineStatus(
        message: localizations.catalogCorruption,
      ),
      IntentionCatalogRecoveryUnexpected() => IntentionCatalogInlineStatus(
        message: localizations.catalogUnexpectedFailure,
      ),
    };
  }
}
