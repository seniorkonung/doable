import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/graph_seed.dart';

/// Число сущностей графа профиля решения 15 дизайна: пример владельца
/// продукта.
const graphLogProfileEntities = 1000000;

/// Граф из [entities] сущностей формата данных графа в одних и тех же
/// пропорциях при любом размере: на тысячу сущностей — тег, 200 намерений,
/// 200 назначений тегов, 300 долговременных связей и 299 дневных выборов с
/// путями из 1–5 шагов.
///
/// Последнее намерение — узел каскада: его [hubRelations] активных связей
/// входят в число связей графа, а остальные связи соединяют прочие
/// намерения полосами, первая из которых — цепочка путей дневных выборов.
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

  final int entities;
  final int hubRelations;
  final int _scale;

  int get tags => _scale;
  int get intentions => 200 * _scale;
  int get tagAssignments => intentions;
  int get longTermRelations => 300 * _scale;
  int get dailyChoices => 299 * _scale;

  /// Количества записей файла формата, который описывает граф.
  GraphRecordCounts get counts => GraphRecordCounts(
    tags: tags,
    intentions: intentions,
    tagAssignments: tagAssignments,
    longTermRelations: longTermRelations,
    dailyChoices: dailyChoices,
  );

  /// Намерения полос: все, кроме узла каскада.
  int get _laneIntentions => intentions - 1;

  int get _laneRelations => longTermRelations - hubRelations;

  IntentionId intentionId(int index) =>
      (IntentionId.decode(_id(2, index)) as IntentionIdDecodingSuccess).id;

  IntentionId get hubIntentionId => intentionId(intentions - 1);

  TagId tagId(int index) =>
      (TagId.decode(_id(1, index)) as TagIdDecodingSuccess).id;

  DailyChoiceId dailyChoiceId(int index) =>
      (DailyChoiceId.decode(_id(4, index)) as DailyChoiceIdDecodingSuccess).id;

  String intentionTitle(int index) => index % 7 == 0
      ? 'Намерение $index — подробное название с целью и контекстом'
      : 'Намерение $index';

  String? intentionDescription(int index) => index % 3 == 0
      ? 'Зачем: шаг $index большой цели.\n'
            'Как понять, что готово: результат проверен и записан.'
      : null;

  /// Вставляет граф в пустую базу [database] одной транзакцией при
  /// выключенном захвате фактов, как замена графа: лог остаётся на позиции 0.
  void populate(sqlite.Database database) {
    final statements = [
      database.prepare('INSERT INTO tags (id, name) VALUES (?, ?)'),
      database.prepare('''INSERT INTO intentions
        (id, title, description, is_action_ready, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)'''),
      database.prepare('''INSERT INTO tag_assignments (tag_id, intention_id)
        VALUES (?, ?)'''),
      database.prepare('''INSERT INTO long_term_relations
        (id, source_intention_id, related_intention_id, type, priority,
         description, is_archived)
        VALUES (?, ?, ?, ?, ?, ?, ?)'''),
      database.prepare('''INSERT INTO daily_choices
        (id, source_intention_id, selected_intention_id, choice_date,
         description, is_completed, scheduled_minute, priority)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)'''),
      database.prepare('''INSERT INTO daily_choice_path_steps
        (id, daily_choice_id, long_term_relation_id, previous_step_id)
        VALUES (?, ?, ?, ?)'''),
    ];
    final [
      insertTag,
      insertIntention,
      insertAssignment,
      insertRelation,
      insertChoice,
      insertStep,
    ] = statements;
    try {
      seedRawGraph(database, () {
        for (var tag = 0; tag < tags; tag++) {
          insertTag.execute([_id(1, tag), 'Тег $tag']);
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
        final firstDay = DateTime.utc(2021);
        var step = 0;
        for (var choice = 0; choice < dailyChoices; choice++) {
          final source = choice * 13 % _laneIntentions;
          final length = choice % 5 + 1;
          final day = firstDay.add(Duration(days: choice ~/ 150));
          insertChoice.execute([
            _id(4, choice),
            _id(2, source),
            _id(2, (source + length) % _laneIntentions),
            CalendarDate.fromParts(
              day.year,
              day.month,
              day.day,
            ).toCanonicalString(),
            choice % 10 == 0 ? 'Выбор $choice: что сделать сегодня' : null,
            choice % 2,
            choice % 3 == 0 ? null : choice * 37 % 1440,
            choice % 4 + 1,
          ]);
          String? previous;
          for (var offset = 0; offset < length; offset++) {
            final stepId = _id(5, step++);
            // Связь первой полосы с номером n ведёт от намерения n к n + 1.
            insertStep.execute([
              stepId,
              _id(4, choice),
              _id(3, (source + offset) % _laneIntentions),
              previous,
            ]);
            previous = stepId;
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
