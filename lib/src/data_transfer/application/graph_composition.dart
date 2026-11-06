/// Состав графа намерений: число сущностей каждого вида вместе с
/// архивированными — столько записей каждого вида попадёт в файл экспорта.
/// Надгробия удалённых звеньев путей сущностями не считаются.
final class GraphComposition {
  const GraphComposition({
    required this.intentionCount,
    required this.relationCount,
    required this.actionCount,
    required this.tagCount,
  });

  final int intentionCount;

  /// Число долговременных связей.
  final int relationCount;

  final int actionCount;
  final int tagCount;

  /// В графе нет ни одного намерения, ни одного тега и ни одного действия.
  /// Действия остаются и без намерений: их пути хранят удалённые намерения.
  bool get isEmpty => intentionCount == 0 && tagCount == 0 && actionCount == 0;

  @override
  bool operator ==(Object other) =>
      other is GraphComposition &&
      other.intentionCount == intentionCount &&
      other.relationCount == relationCount &&
      other.actionCount == actionCount &&
      other.tagCount == tagCount;

  @override
  int get hashCode =>
      Object.hash(intentionCount, relationCount, actionCount, tagCount);
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
