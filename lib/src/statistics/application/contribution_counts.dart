/// Нарушен инвариант прочитанной статистики. На границе чтения
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
