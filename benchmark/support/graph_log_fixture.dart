import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/graph_seed.dart';
import '../../test/support/tag_positions.dart';

/// Число сущностей графа профиля решения 15 дизайна: пример владельца
/// продукта.
const graphLogProfileEntities = 1000000;

/// Граф из [entities] сущностей формата данных графа в одних и тех же
/// пропорциях при любом размере: на тысячу сущностей — тег, 200 намерений,
/// 200 назначений тегов, 300 долговременных связей, 294 действия с путями из
/// 1–5 звеньев, два надгробия намерений и три надгробия пар. Действия идут по
/// [actionsPerDay] в день.
///
/// Последнее намерение — узел каскада: его [hubRelations] активных связей
/// входят в число связей графа, а остальные связи соединяют прочие
/// намерения полосами, первая из которых — цепочка путей действий. Три
/// последних действия каждой тысячи ведут путь через удалённое: к удалённому
/// конечному намерению, от удалённого корневого и по удалённой связи.
final class GraphLogFixture {
  GraphLogFixture(this.entities, {this.hubRelations = 0})
    : _scale = entities ~/ 1000 {
    if (entities % 1000 != 0 || entities == 0) {
      throw ArgumentError.value(entities, 'entities', 'нужно кратное 1000');
    }
    if (hubRelations < 0 || hubRelations > 100 * _scale) {
      throw ArgumentError.value(hubRelations, 'hubRelations');
    }
  }

  /// Наибольшее число действий одного дня.
  static const actionsPerDay = 60;

  final int entities;
  final int hubRelations;
  final int _scale;

  int get tags => _scale;
  int get intentions => 200 * _scale;
  int get tagAssignments => intentions;
  int get longTermRelations => 300 * _scale;
  int get deletedIntentions => 2 * _scale;
  int get deletedRelationPairs => 3 * _scale;
  int get actions => 294 * _scale;

  /// Количества записей файла формата, который описывает граф.
  GraphRecordCounts get counts => GraphRecordCounts(
    tags: tags,
    intentions: intentions,
    deletedIntentions: deletedIntentions,
    tagAssignments: tagAssignments,
    longTermRelations: longTermRelations,
    deletedRelationPairs: deletedRelationPairs,
    actions: actions,
    dailyChoices: 0,
  );

  /// Намерения полос: все, кроме узла каскада.
  int get _laneIntentions => intentions - 1;

  int get _laneRelations => longTermRelations - hubRelations;

  /// Действия с путями только из существующих намерений и связей.
  int get connectedActions => actions - 3 * _scale;

  IntentionId intentionId(int index) =>
      (IntentionId.decode(_id(2, index)) as IntentionIdDecodingSuccess).id;

  IntentionId get hubIntentionId => intentionId(intentions - 1);

  TagId tagId(int index) =>
      (TagId.decode(_id(1, index)) as TagIdDecodingSuccess).id;

  /// Действие с номером [index]; у действия с номером 5k + 4 путь из пяти
  /// звеньев по существующим связям.
  ActionId actionId(int index) {
    if (index >= connectedActions) throw RangeError.value(index, 'index');
    return (ActionId.decode(_id(4, index)) as ActionIdDecodingSuccess).id;
  }

  String intentionTitle(int index) => index % 7 == 0
      ? 'Намерение $index — подробное название с целью и контекстом'
      : 'Намерение $index';

  String? intentionDescription(int index) => index % 3 == 0
      ? 'Зачем: шаг $index большой цели.\n'
            'Как понять, что готово: результат проверен и записан.'
      : null;

  /// Номера намерений пути действия [action]: удалённые намерения имеют
  /// номера от [intentions], которых нет у существующих.
  List<int> _path(int action) {
    final source = action * 13 % _laneIntentions;
    if (action < connectedActions) {
      return [
        for (var offset = 0; offset <= action % 5 + 1; offset++)
          (source + offset) % _laneIntentions,
      ];
    }
    final special = action - connectedActions;
    final deleted = intentions + 2 * (special ~/ 3);
    // Полосы соединяют намерения со сдвигом не больше двух, поэтому у пары
    // со сдвигом пять связи нет.
    return switch (special % 3) {
      0 => [source, (source + 1) % _laneIntentions, deleted],
      1 => [deleted + 1, source, (source + 1) % _laneIntentions],
      _ => [source, (source + 5) % _laneIntentions],
    };
  }

  /// Вставляет граф в пустую базу [database] одной транзакцией при
  /// выключенном захвате фактов, как замена графа: лог остаётся на позиции 0.
  void populate(sqlite.Database database) {
    final statements = [
      database.prepare(
        'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
      ),
      database.prepare('''INSERT INTO intentions
        (id, title, description, is_action_ready, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)'''),
      database.prepare('''INSERT INTO tag_assignments (tag_id, intention_id)
        VALUES (?, ?)'''),
      database.prepare('''INSERT INTO long_term_relations
        (id, source_intention_id, related_intention_id, type, priority,
         description, is_archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)'''),
      database.prepare(
        'INSERT INTO deleted_intentions (intention_id, title) VALUES (?, ?)',
      ),
      database.prepare('''INSERT INTO deleted_relation_pairs
        (source_intention_id, related_intention_id, type) VALUES (?, ?, ?)'''),
      database.prepare('''INSERT INTO actions
        (id, title, description, date, scheduled_hour, priority, is_completed,
         created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'''),
      database.prepare('''INSERT INTO action_path_items
        (action_id, position, intention_id, previous_intention_id)
        VALUES (?, ?, ?, ?)'''),
    ];
    final [
      insertTag,
      insertIntention,
      insertAssignment,
      insertRelation,
      insertDeletedIntention,
      insertDeletedPair,
      insertAction,
      insertItem,
    ] = statements;
    try {
      seedRawGraph(database, () {
        for (var tag = 0; tag < tags; tag++) {
          insertTag.execute([_id(1, tag), 'Тег $tag', tagPositionKey(tag)]);
        }
        final createdAt = DateTime.utc(2024).microsecondsSinceEpoch;
        for (var intention = 0; intention < intentions; intention++) {
          final timestamp =
              createdAt + intention * Duration.microsecondsPerSecond;
          insertIntention.execute([
            _id(2, intention),
            intentionTitle(intention),
            intentionDescription(intention),
            intention % 2,
            timestamp,
            timestamp,
          ]);
        }
        for (var intention = 0; intention < intentions; intention++) {
          insertAssignment.execute([
            _id(1, intention % tags),
            _id(2, intention),
          ]);
        }
        for (var relation = 0; relation < longTermRelations; relation++) {
          final (source, related, lane) = _relationEnds(relation);
          insertRelation.execute([
            _id(3, relation),
            _id(2, source),
            _id(2, related),
            relation.isEven ? 'need' : 'can',
            relation % 4 + 1,
            relation % 5 == 0 ? 'Связь $relation: почему это важно' : null,
            lane == 2 && relation % 20 == 19 ? 1 : 0,
          ]);
        }
        // Надгробия вставляются до путей, которые на них ссылаются.
        for (var action = connectedActions; action < actions; action++) {
          final path = _path(action);
          final (source, related) = (action - connectedActions) % 3 == 0
              ? (path[1], path[2])
              : (path[0], path[1]);
          for (final deleted in path.where((index) => index >= intentions)) {
            insertDeletedIntention.execute([
              _id(2, deleted),
              'Удалённое намерение $deleted',
            ]);
          }
          insertDeletedPair.execute([
            _id(2, source),
            _id(2, related),
            action.isEven ? 'need' : 'can',
          ]);
        }
        final firstDay = DateTime.utc(2021);
        for (var action = 0; action < actions; action++) {
          final day = firstDay.add(Duration(days: action ~/ actionsPerDay));
          final timestamp = createdAt + action * Duration.microsecondsPerSecond;
          insertAction.execute([
            _id(4, action),
            'Действие $action',
            action % 10 == 0 ? 'Действие $action: что сделать сегодня' : null,
            CalendarDate.fromParts(
              day.year,
              day.month,
              day.day,
            ).toCanonicalString(),
            action % 3 == 0 ? null : action * 7 % 24,
            action % 4 + 1,
            action % 2,
            timestamp,
            timestamp,
          ]);
          final path = _path(action);
          for (var position = 0; position < path.length; position++) {
            insertItem.execute([
              _id(4, action),
              position,
              _id(2, path[position]),
              position == 0 ? null : _id(2, path[position - 1]),
            ]);
          }
        }
      });
    } finally {
      for (final statement in statements) {
        statement.close();
      }
    }
  }

  /// Концы связи [relation] и номер её полосы; у связей узла каскада полосы
  /// нет.
  (int, int, int?) _relationEnds(int relation) {
    if (relation >= _laneRelations) {
      return (intentions - 1, relation - _laneRelations, null);
    }
    final source = relation % _laneIntentions;
    final lane = relation ~/ _laneIntentions + 1;
    return (source, (source + lane) % _laneIntentions, lane);
  }

  /// Идентификатор сущности вида [kind] с номером [index]: UUID версии 7 с
  /// видом в третьей группе, поэтому виды не пересекаются.
  static String _id(int kind, int index) =>
      '018f0b5d-6b2e-7c80-8${kind}00-${index.toRadixString(16).padLeft(12, '0')}';
}
