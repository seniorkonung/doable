/// Нарушен числовой инвариант прочитанной статистики. На границе чтения
/// адаптер преобразует это исключение в отказ повреждения всего результата.
final class StatisticsDataValidationException implements Exception {
  const StatisticsDataValidationException();
}

final class ContributionCounts {
  factory ContributionCounts({
    required int planned,
    required int contribution,
  }) {
    if (planned < 0 || contribution < 0 || contribution > planned) {
      throw const StatisticsDataValidationException();
    }
    return ContributionCounts._(planned, contribution);
  }

  const ContributionCounts._(this.planned, this.contribution);

  final int planned;
  final int contribution;

  int get uncompleted => planned - contribution;
}

/// Невыполненные выборы до местной даты и начиная с неё соответственно.
final class UncompletedSplit {
  factory UncompletedSplit({required int missed, required int upcoming}) {
    if (missed < 0 || upcoming < 0) {
      throw const StatisticsDataValidationException();
    }
    return UncompletedSplit._(missed, upcoming);
  }

  const UncompletedSplit._(this.missed, this.upcoming);

  final int missed;
  final int upcoming;
}

/// Каждый выбор периода учтён один раз независимо от выбранного вида
/// и числа намерений, которым он засчитан.
final class StatisticsPeriodSummary {
  factory StatisticsPeriodSummary({
    required ContributionCounts counts,
    required UncompletedSplit uncompleted,
  }) {
    if (uncompleted.missed + uncompleted.upcoming != counts.uncompleted) {
      throw const StatisticsDataValidationException();
    }
    return StatisticsPeriodSummary._(counts, uncompleted);
  }

  const StatisticsPeriodSummary._(this.counts, this.uncompleted);

  final ContributionCounts counts;
  final UncompletedSplit uncompleted;
}
