import '../graph_format/graph_format_records.dart';
import '../graph_snapshots/graph_snapshot_store.dart';

/// Что изменилось в графе между двумя позициями лога.
sealed class GraphChangeSummary {
  const GraphChangeSummary();
}

/// Числа намерений, тегов, долговременных связей и дневных выборов, которые
/// добавлены, изменены и удалены между позициями.
final class GraphChangeCounts extends GraphChangeSummary {
  const GraphChangeCounts({
    required this.added,
    required this.changed,
    required this.deleted,
  });

  final int added;
  final int changed;
  final int deleted;
}

/// Между позициями граф заменялся импортом или восстановлением копии, поэтому
/// числа не считаются.
final class GraphDataReplaced extends GraphChangeSummary {
  const GraphDataReplaced();
}

/// Есть ли сущность до диапазона и после него.
typedef _Presence = ({bool existed, bool exists});

/// Подсчёт сводки изменений графа только по фактам пакетов лога после
/// начальной позиции; снимки он не читает.
///
/// Сводка держит в памяти по одной отметке на каждую затронутую сущность, а
/// не состояния графа, поэтому её цена зависит от числа пакетов и затронутых
/// сущностей, но не от размера графа. Её можно продолжить пакетами после
/// [position], не перечитывая уже учтённые.
final class GraphChangeTally {
  /// Сводка без пакетов после позиции [after]: изменений нет.
  GraphChangeTally({required int after}) : _position = after;

  /// Сводка пакетов диапазона чтения истории [history] после [after] не
  /// дальше [upTo].
  static Future<GraphChangeTally> ofRange(
    GraphHistoryRead history, {
    required int after,
    required int upTo,
  }) async {
    final tally = GraphChangeTally(after: after);
    await for (final package in history.readPackages(
      after: after,
      upTo: upTo,
    )) {
      tally.add(package);
    }
    return tally;
  }

  int _position;
  bool _replaced = false;
  final _presences = <GraphEntityKey, _Presence>{};

  /// Намерения, назначения тегов которых менялись.
  final _reassigned = <IntentionKey>{};

  /// Позиция последнего учтённого пакета, а без пакетов — начальная.
  int get position => _position;

  /// Учитывает следующий пакет. Пакет не после [position] даёт [StateError]
  /// и сводку не меняет.
  void add(GraphHistoryPackage package) {
    if (package.position <= _position) {
      throw StateError('Пакет лога не после конца сводки.');
    }
    _position = package.position;
    if (_replaced) return;
    switch (package) {
      case GraphHistoryReset():
        _replaced = true;
        _presences.clear();
        _reassigned.clear();
      case GraphHistoryChange(:final facts):
        for (final fact in facts) {
          switch (fact) {
            case GraphEntityCreated(:final record):
              _note(record.key, existed: false, exists: true);
            case GraphEntityChanged(:final record):
              _note(record.key, existed: true, exists: true);
            case GraphEntityDeleted(:final entity):
              _note(entity, existed: true, exists: false);
          }
        }
    }
  }

  /// Первый факт сущности говорит, была ли она до диапазона, последний — есть
  /// ли она после.
  void _note(
    GraphEntityKey entity, {
    required bool existed,
    required bool exists,
  }) {
    if (entity case TagAssignmentKey(:final assignment)) {
      _reassigned.add(IntentionKey(assignment.intentionId));
      return;
    }
    _presences.update(
      entity,
      (presence) => (existed: presence.existed, exists: exists),
      ifAbsent: () => (existed: existed, exists: exists),
    );
  }

  /// Сводка учтённых пакетов. Сущность, которая была и есть, изменена, даже
  /// если правка вернула прежнее значение; которая есть только после —
  /// добавлена, была только до — удалена.
  GraphChangeSummary get summary {
    if (_replaced) return const GraphDataReplaced();
    var added = 0;
    var changed = 0;
    var deleted = 0;
    for (final presence in _presences.values) {
      switch (presence) {
        case (existed: true, exists: true):
          changed++;
        case (existed: false, exists: true):
          added++;
        case (existed: true, exists: false):
          deleted++;
        case (existed: false, exists: false):
          break;
      }
    }
    // Назначение ссылается только на существующее намерение, поэтому
    // намерение без собственных фактов было в диапазоне всё время.
    for (final intention in _reassigned) {
      if (!_presences.containsKey(intention)) changed++;
    }
    return GraphChangeCounts(added: added, changed: changed, deleted: deleted);
  }
}
