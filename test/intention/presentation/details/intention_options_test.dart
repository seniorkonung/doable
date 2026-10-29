import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'details_test_support.dart';

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));

  test('у активного намерения пункты стоят в порядке «Изменить», '
      '«Архивировать», «Удалить» со значками, а удаление — в опасном тоне', () {
    final items = intentionOptions(ru, _loaded());

    expect(items.map((item) => item.name), [
      'Изменить',
      'Архивировать',
      'Удалить',
    ]);
    expect(items.map((item) => item.icon), [
      DoableIconData.edit,
      DoableIconData.archive,
      DoableIconData.delete,
    ]);
    expect(items.map((item) => item.value), [
      IntentionOption.edit,
      IntentionOption.archive,
      IntentionOption.delete,
    ]);
    expect(items.first.hint, isNull);
    expect(items.last.tone, OptionRowTone.danger);
  });

  test('архивирование поясняет судьбу активных связей или намерения без них, '
      'архивные связи не считаются', () {
    expect(
      intentionOptions(ru, _loaded())[1].hint,
      'Останется в сохранённых путях и не будет предлагаться в новых',
    );
    expect(
      intentionOptions(
        ru,
        _loaded(counts: testRelationCounts(archivedNeedIncoming: 2)),
      )[1].hint,
      'Останется в сохранённых путях и не будет предлагаться в новых',
    );
    expect(
      intentionOptions(
        ru,
        _loaded(counts: testRelationCounts(activeCanOutgoing: 1)),
      )[1].hint,
      'Его связи архивируются вместе с ним',
    );
  });

  test('у архивированного намерения вместо архивирования стоит '
      'восстановление с пояснением по связям любого архивного состояния', () {
    final alone = intentionOptions(ru, _loaded(archived: true))[1];
    expect(alone.name, 'Восстановить из архива');
    expect(alone.icon, DoableIconData.unarchive);
    expect(alone.value, IntentionOption.restore);
    expect(alone.hint, 'Новые пути снова смогут его использовать');

    for (final counts in [
      testRelationCounts(archivedCanIncoming: 1),
      testRelationCounts(activeNeedOutgoing: 1),
    ]) {
      expect(
        intentionOptions(ru, _loaded(archived: true, counts: counts))[1].hint,
        'Его связи останутся в архиве, пока вы их не восстановите',
      );
    }
    // Дневные выборы не остаются в архиве, поэтому пояснение их не касается.
    expect(
      intentionOptions(
        ru,
        _loaded(archived: true, counts: testRelationCounts(dailySource: 1)),
      )[1].hint,
      'Новые пути снова смогут его использовать',
    );
  });

  test('доступное удаление поясняет, что теги сохранятся', () {
    final delete = intentionOptions(ru, _loaded())[2];
    expect(delete.value, IntentionOption.delete);
    expect(delete.hint, 'Его теги сохранятся');
  });

  test('удаление выключено, пока его блокируют связи любого архивного '
      'состояния, дневные выборы или и то, и другое, и называет причину', () {
    for (final (counts, reason) in [
      (testRelationCounts(activeNeedIncoming: 1), 'Сначала удалите его связи'),
      (testRelationCounts(archivedCanIncoming: 1), 'Сначала удалите его связи'),
      (
        testRelationCounts(dailySelected: 1),
        'Сначала удалите его дневные выборы',
      ),
      (
        testRelationCounts(archivedNeedOutgoing: 1, dailySource: 2),
        'Сначала удалите его связи и дневные выборы',
      ),
    ]) {
      for (final archived in [false, true]) {
        final delete = intentionOptions(
          ru,
          _loaded(archived: archived, counts: counts),
        )[2];
        expect(delete.value, isNull);
        expect(delete.hint, reason);
      }
    }
  });

  test('во время операции все пункты недоступны и просят дождаться её '
      'окончания, а заблокированное удаление сохраняет свою причину', () {
    for (final archived in [false, true]) {
      final items = intentionOptions(
        ru,
        _loaded(archived: archived, running: true),
      );
      expect(items.map((item) => item.value), everyElement(isNull));
      expect(
        items.map((item) => item.hint),
        everyElement('Дождитесь окончания текущего изменения'),
      );
    }

    final blocked = intentionOptions(
      ru,
      _loaded(running: true, counts: testRelationCounts(dailySource: 1)),
    );
    expect(blocked.map((item) => item.value), everyElement(isNull));
    expect(blocked.map((item) => item.hint), [
      'Дождитесь окончания текущего изменения',
      'Дождитесь окончания текущего изменения',
      'Сначала удалите его дневные выборы',
    ]);
  });

  test('«Изменить» ждёт снимок после подтверждённого изменения, а остальные '
      'пункты доступны', () {
    final items = intentionOptions(ru, _loaded(awaitingSnapshot: true));
    expect(items.first.value, isNull);
    expect(items.first.hint, 'Дождитесь окончания текущего изменения');
    expect(items[1].value, IntentionOption.archive);
    expect(items[2].value, IntentionOption.delete);
  });

  test('тексты пунктов переведены на английский', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final active = intentionOptions(
      en,
      _loaded(counts: testRelationCounts(activeNeedIncoming: 1)),
    );
    expect(active.map((item) => (item.name, item.hint)), [
      ('Edit', null),
      ('Archive', 'Its relations are archived with it'),
      ('Delete', 'Delete its relations first'),
    ]);
    expect(intentionOptions(en, _loaded()).map((item) => item.hint), [
      null,
      'It stays in saved paths, new ones will not use it',
      'Its tags stay',
    ]);
    expect(
      intentionOptions(
        en,
        _loaded(archived: true, counts: testRelationCounts(dailySource: 1)),
      ).map((item) => (item.name, item.hint)),
      [
        ('Edit', null),
        ('Restore from archive', 'New paths can use it again'),
        ('Delete', 'Delete its daily choices first'),
      ],
    );
    expect(
      intentionOptions(
        en,
        _loaded(
          archived: true,
          counts: testRelationCounts(archivedNeedIncoming: 1, dailySource: 1),
        ),
      ).map((item) => item.hint).skip(1),
      [
        'Its relations stay archived until you restore them',
        'Delete its relations and daily choices first',
      ],
    );
    expect(
      intentionOptions(en, _loaded(running: true)).map((item) => item.hint),
      everyElement('Wait for the current change to finish'),
    );
  });
}

IntentionDetailsLoaded _loaded({
  bool archived = false,
  bool running = false,
  bool awaitingSnapshot = false,
  RelationCounts? counts,
}) => IntentionDetailsLoaded(
  details: IntentionDetails(
    intention: testDetailsIntention(
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
    ),
    relationCounts: counts ?? testRelationCounts(),
  ),
  revision: const TestDetailsRevision(0),
  isOperationRunning: running,
  isAwaitingConfirmedSnapshot: awaitingSnapshot,
);
