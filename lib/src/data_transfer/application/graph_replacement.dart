import 'dart:async';

import '../../graph/application/graph_change.dart';
import '../../graph_snapshots/graph_snapshot_store.dart'
    show GraphSnapshotCorruption, UnregisteredGraphSnapshot;

/// Замена графа отменена: её транзакция откатана, и граф, копии, лог фактов
/// и реестр снимков остались прежними.
final class GraphReplacementCancelled implements Exception {
  const GraphReplacementCancelled();
}

/// Отмена замены графа: вызывающий её запрашивает, а замена принимает её
/// только до своей точки невозврата.
///
/// Запрос отмены и прохождение точки невозврата исключают друг друга. Оба
/// решаются синхронно, поэтому запрос, пришедший в момент проверки в точке
/// невозврата, либо принят и откатывает замену, либо не принят, и
/// запросивший узнаёт об этом из [request].
final class GraphReplacementCancellation {
  /// [onPointOfNoReturn] вызывается, когда замена проходит точку невозврата:
  /// с этого момента отмена не принимается.
  GraphReplacementCancellation({
    this._onPointOfNoReturn = _ignorePointOfNoReturn,
  });

  final void Function() _onPointOfNoReturn;
  var _state = _GraphReplacementCancellationState.open;
  final _requested = Completer<void>();

  /// Завершается, когда отмена принята. По нему прекращается подготовка
  /// замены, которая не может проверить отмену синхронно, — запись снимка
  /// замены в отдельном изоляте.
  Future<void> get requested => _requested.future;

  /// Запрашивает отмену и сообщает, принята ли она.
  ///
  /// До точки невозврата отмена принимается: замена откатывается и даёт
  /// [GraphReplacementCancelled]. После точки невозврата отмена не
  /// принимается, и замена завершается так же, как без запроса.
  bool request() {
    switch (_state) {
      case _GraphReplacementCancellationState.open:
        _state = _GraphReplacementCancellationState.requested;
        _requested.complete();
        return true;
      case _GraphReplacementCancellationState.requested:
        return true;
      case _GraphReplacementCancellationState.passedPointOfNoReturn:
        return false;
    }
  }

  /// Проверка отмены заменой: принятая отмена даёт
  /// [GraphReplacementCancelled].
  void throwIfRequested() {
    if (_state == _GraphReplacementCancellationState.requested) {
      throw const GraphReplacementCancelled();
    }
  }

  /// Последняя проверка отмены заменой — точка невозврата. Принятая отмена
  /// даёт [GraphReplacementCancelled]; иначе отмена с этого момента не
  /// принимается, а вызывающий узнаёт о прохождении точки.
  void passPointOfNoReturn() {
    throwIfRequested();
    _state = _GraphReplacementCancellationState.passedPointOfNoReturn;
    _onPointOfNoReturn();
  }
}

enum _GraphReplacementCancellationState {
  open,
  requested,
  passedPointOfNoReturn,
}

void _ignorePointOfNoReturn() {}

/// Записи снимка замены нарушают правило целостности графа, которого не
/// выражает схема хранилища: путь дневного выбора не непрерывен от источника
/// до выбранного намерения, или после вставки в графе не столько записей
/// каждого вида, сколько в количествах снимка.
///
/// Отказ не несёт прочитанных данных: в них пользовательский текст.
final class GraphReplacementRecordsRejected implements Exception {
  const GraphReplacementRecordsRejected();
}

/// Атомарная замена всего графа намерений состоянием снимка замены
/// (ADR-0036).
abstract interface class GraphReplacement {
  /// Заменяет весь граф записями снимка замены [snapshot] одной транзакцией
  /// верхнего уровня, в которой захват фактов выключен.
  ///
  /// Транзакция удаляет прежний граф и вставляет записи снимка небольшими
  /// пакетами операторов. Записи проверяют схема хранилища — ссылки,
  /// уникальность и активность участников активной долговременной связи — и
  /// общая проверка непрерывности пути дневного выбора. Условия, которые
  /// проверяются только при создании и изменении сущностей, — активность
  /// участников и связей пути, готовность выбранного намерения, — к записям
  /// снимка не применяются. Затем количества записей графа сверяются с
  /// количествами снимка. Если прежний граф не пуст, транзакция добавляет
  /// копию перед заменой с позицией лога до замены и сводкой изменений с
  /// предыдущей копии. Наконец она регистрирует [snapshot] на следующей
  /// позиции и пишет на ней пакет «сброс», который на него ссылается.
  ///
  /// После подтверждения транзакции начинается новая эпоха ревизий, кэши
  /// графа сбрасываются, наблюдатели всех сущностей и состава графа
  /// перечитывают их, наблюдатели лога получают позицию пакета «сброс», а
  /// наблюдатели списка копий — список с копией перед заменой, если она
  /// добавлена. Результат несёт изменение «граф заменён» с первой ревизией
  /// новой эпохи.
  ///
  /// [onProgress] получает долю обработанных записей — удалённых записей
  /// прежнего графа и вставленных записей снимка, — когда она достигает
  /// следующей сотой доли, и последней — полную. Перед каждым пакетом
  /// операторов проверяется отмена [cancellation]: принятая отмена даёт
  /// [GraphReplacementCancelled].
  ///
  /// Последний раз отмена проверяется в транзакции сразу перед COMMIT —
  /// после сверки количеств, копии перед заменой, регистрации снимка,
  /// пакета «сброс» и включения захвата. Эта проверка — точка невозврата
  /// [GraphReplacementCancellation.passPointOfNoReturn]. Отмена, принятая до
  /// неё, откатывает всю транзакцию. После неё отмена не принимается, а
  /// вызывающий узнаёт о прохождении точки до подтверждения транзакции;
  /// отменить замену уже нельзя, и откатить её может только отказ COMMIT.
  ///
  /// Любой отказ откатывает всю транзакцию: граф, копии, лог и реестр
  /// снимков остаются прежними, а файл [snapshot] остаётся вызывающему.
  /// Эпоха ревизий, кэши и наблюдатели при этом не затрагиваются. Снимок, не
  /// прошедший проверку, даёт [GraphSnapshotCorruption], записи, нарушающие
  /// правило вне схемы, — [GraphReplacementRecordsRejected], а отказ
  /// хранилища, в том числе нарушение схемы и нехватка места, передаётся
  /// исключением хранилища.
  Future<ConfirmedGraphReplacement> replaceGraph(
    UnregisteredGraphSnapshot snapshot, {
    required void Function(double share) onProgress,
    required GraphReplacementCancellation cancellation,
  });
}
