import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../application/statistics_read_contract.dart';

enum StatisticsReadStage { initial, refresh, more }

String statisticsReadFailureMessage(
  AppLocalizations texts,
  StatisticsReadFailure failure,
  StatisticsReadStage stage,
) => switch ((stage, failure)) {
  (StatisticsReadStage.initial, StatisticsReadUnavailableFailure()) =>
    texts.statisticsUnavailable,
  (StatisticsReadStage.initial, StatisticsReadCorruptionFailure()) =>
    texts.statisticsCorruption,
  (
    StatisticsReadStage.initial,
    StatisticsReadUnexpectedFailure() ||
        StatisticsSnapshotExpired() ||
        StatisticsIntentionNotFoundFailure(),
  ) =>
    texts.statisticsUnexpectedFailure,
  (StatisticsReadStage.refresh, StatisticsReadUnavailableFailure()) =>
    texts.statisticsRefreshUnavailable,
  (StatisticsReadStage.refresh, StatisticsReadCorruptionFailure()) =>
    texts.statisticsRefreshCorruption,
  (
    StatisticsReadStage.refresh,
    StatisticsReadUnexpectedFailure() ||
        StatisticsSnapshotExpired() ||
        StatisticsIntentionNotFoundFailure(),
  ) =>
    texts.statisticsRefreshUnexpectedFailure,
  (StatisticsReadStage.more, StatisticsReadUnavailableFailure()) =>
    texts.statisticsLoadMoreUnavailable,
  (StatisticsReadStage.more, StatisticsReadCorruptionFailure()) =>
    texts.statisticsLoadMoreCorruption,
  (
    StatisticsReadStage.more,
    StatisticsReadUnexpectedFailure() ||
        StatisticsSnapshotExpired() ||
        StatisticsIntentionNotFoundFailure(),
  ) =>
    texts.statisticsLoadMoreUnexpectedFailure,
};

final class StatisticsReadNotice extends StatelessWidget {
  const StatisticsReadNotice({
    required this.message,
    this.onRetry,
    this.scrollMessage = false,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool scrollMessage;

  @override
  Widget build(BuildContext context) {
    final notice = Semantics(
      // Сообщает об обновлении без переноса доступного фокуса.
      // https://api.flutter.dev/flutter/semantics/SemanticsProperties/liveRegion.html
      liveRegion: true,
      child: Text(message),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scrollMessage)
            Flexible(
              // Крупный текст прокручивается отдельно; повтор остаётся видимым.
              // https://api.flutter.dev/flutter/widgets/SingleChildScrollView-class.html
              child: SingleChildScrollView(primary: false, child: notice),
            )
          else
            notice,
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
        ],
      ),
    );
  }
}
