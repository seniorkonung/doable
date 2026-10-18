/// Состав графа намерений: число сущностей каждого вида вместе с
/// архивированными — столько записей каждого вида попадёт в файл экспорта.
final class GraphComposition {
  const GraphComposition({
    required this.intentionCount,
    required this.relationCount,
    required this.dailyChoiceCount,
    required this.tagCount,
  });

  final int intentionCount;

  /// Число долговременных связей.
  final int relationCount;

  final int dailyChoiceCount;
  final int tagCount;

  /// В графе нет ни одного намерения и ни одного тега.
  bool get isEmpty => intentionCount == 0 && tagCount == 0;

  @override
  bool operator ==(Object other) =>
      other is GraphComposition &&
      other.intentionCount == intentionCount &&
      other.relationCount == relationCount &&
      other.dailyChoiceCount == dailyChoiceCount &&
      other.tagCount == tagCount;

  @override
  int get hashCode =>
      Object.hash(intentionCount, relationCount, dailyChoiceCount, tagCount);
}

/// Исход чтения состава графа.
sealed class GraphCompositionRead {
  const GraphCompositionRead();
}

final class GraphCompositionReadSucceeded extends GraphCompositionRead {
  const GraphCompositionReadSucceeded(this.composition);

  final GraphComposition composition;
}

/// Состав не прочитан. Отказ не означает пустого графа; его причину, в том
/// числе повреждение хранилища, различает только диагностика.
final class GraphCompositionReadFailed extends GraphCompositionRead {
  const GraphCompositionReadFailed();
}

/// Состав графа для раздела «Данные»: по нему экспорт пустого графа
/// недоступен, а панель экспорта показывает состав будущего файла.
abstract interface class GraphCompositionSource {
  /// Наблюдает состав графа: первое значение — состав при подписке, затем
  /// новое значение после каждого подтверждённого изменения, которое меняет
  /// состав. Каждый состав прочитан на одном подтверждённом состоянии графа.
  ///
  /// Отказ чтения — последнее значение: повторное чтение повреждённого
  /// хранилища состав не восстанавливает.
  Stream<GraphCompositionRead> watchComposition();
}
