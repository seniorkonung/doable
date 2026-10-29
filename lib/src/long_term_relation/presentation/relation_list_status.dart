import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../application/relation_group_page.dart';

/// Статус порционного списка, которым владеет общий слой согласования:
/// первое чтение, отказы, подгрузка, обновление и подтверждённый конец.
///
/// Вкладки показывают одинаковые сообщения отказов по категориям, индикатор,
/// живую область и повтор. Обычный повтор предоставляется только при
/// устранимой недоступности; остальные условия повтора задаёт вкладка,
/// передавая или не передавая обработчик.
final class RelationListStatus extends StatelessWidget {
  /// Сообщение вкладки без индикатора и повтора, например пустой список.
  const RelationListStatus({
    required this.message,
    this.progressIndicator = false,
    this.onRetry,
    super.key,
  });

  /// Первое чтение: подтверждённых строк ещё нет.
  factory RelationListStatus.initialLoad(AppLocalizations l10n, {Key? key}) =>
      RelationListStatus(
        message: l10n.relationNeighborhoodSummaryLoading,
        progressIndicator: true,
        key: key,
      );

  /// Отказ первого чтения; это не пустой список.
  factory RelationListStatus.initialFailure(
    AppLocalizations l10n, {
    required RelationGroupReadFailure failure,
    required Future<void> Function()? onRetry,
    Key? key,
  }) => RelationListStatus(
    message: _initialFailureMessage(l10n, failure),
    onRetry: _retryIfUnavailable(failure, onRetry),
    key: key,
  );

  /// Намерение подтверждённо отсутствует.
  factory RelationListStatus.intentionNotFound(
    AppLocalizations l10n, {
    Key? key,
  }) => RelationListStatus(
    message: l10n.relationNeighborhoodIntentionNotFound,
    key: key,
  );

  /// Подгрузка продолжения поверх подтверждённой части.
  factory RelationListStatus.loadingMore(AppLocalizations l10n, {Key? key}) =>
      RelationListStatus(
        message: l10n.relationNeighborhoodLoadingMore,
        progressIndicator: true,
        key: key,
      );

  /// Отказ подгрузки: прежние строки сохранены.
  factory RelationListStatus.loadMoreFailure(
    AppLocalizations l10n, {
    required RelationGroupReadFailure failure,
    required Future<void> Function()? onRetry,
    Key? key,
  }) => RelationListStatus(
    message: _loadMoreFailureMessage(l10n, failure),
    onRetry: _retryIfUnavailable(failure, onRetry),
    key: key,
  );

  /// Прежние строки показаны, пока собирается их замена.
  factory RelationListStatus.refreshing(AppLocalizations l10n, {Key? key}) =>
      RelationListStatus(
        message: l10n.relationNeighborhoodRefreshing,
        progressIndicator: true,
        key: key,
      );

  /// Замену получить не удалось, поэтому показанные строки устарели.
  factory RelationListStatus.refreshFailure(
    AppLocalizations l10n, {
    required RelationGroupReadFailure failure,
    required Future<void> Function()? onRetry,
    Key? key,
  }) => RelationListStatus(
    message: l10n.relationNeighborhoodRefreshFailed,
    onRetry: _retryIfUnavailable(failure, onRetry),
    key: key,
  );

  /// Все строки списка загружены на актуальном снимке.
  factory RelationListStatus.confirmedEnd(AppLocalizations l10n, {Key? key}) =>
      RelationListStatus(
        message: l10n.relationNeighborhoodConfirmedEnd,
        key: key,
      );

  final String message;
  final bool progressIndicator;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: progressIndicator || onRetry != null,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (progressIndicator) ...[
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          if (onRetry case final retry?) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(retry()),
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ],
      ),
    ),
  );
}

Future<void> Function()? _retryIfUnavailable(
  RelationGroupReadFailure failure,
  Future<void> Function()? onRetry,
) => failure is RelationGroupUnavailableFailure ? onRetry : null;

String _initialFailureMessage(
  AppLocalizations l10n,
  RelationGroupReadFailure failure,
) => switch (failure) {
  RelationGroupUnavailableFailure() =>
    l10n.relationNeighborhoodInitialUnavailable,
  RelationGroupCorruptionFailure() =>
    l10n.relationNeighborhoodInitialCorruption,
  RelationGroupUnexpectedFailure() =>
    l10n.relationNeighborhoodInitialUnexpected,
  RelationGroupSnapshotExpired() => l10n.relationNeighborhoodInitialInvalid,
  RelationGroupIntentionNotFoundFailure() =>
    l10n.relationNeighborhoodIntentionNotFound,
};

String _loadMoreFailureMessage(
  AppLocalizations l10n,
  RelationGroupReadFailure failure,
) => switch (failure) {
  RelationGroupUnavailableFailure() =>
    l10n.relationNeighborhoodLoadMoreUnavailable,
  RelationGroupCorruptionFailure() =>
    l10n.relationNeighborhoodLoadMoreCorruption,
  RelationGroupUnexpectedFailure() =>
    l10n.relationNeighborhoodLoadMoreUnexpected,
  RelationGroupSnapshotExpired() || RelationGroupIntentionNotFoundFailure() =>
    l10n.relationNeighborhoodLoadMoreInvalid,
};
