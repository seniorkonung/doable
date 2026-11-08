import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/intention_cascade_execution.dart';
import 'details_test_support.dart';

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  final subject = IntentionCascadeSubject(testDetailsIntentionId(1));
  final revision = const TestDetailsRevision(0);

  test(
    'пункты доступны без последствий при загрузке и отказе предпросмотра',
    () {
      final items = intentionOptions(
        ru,
        _loaded(),
        statePreview: const CascadePreviewUnavailable(),
      );
      expect(items.map((item) => item.value), [
        IntentionOption.edit,
        IntentionOption.archive,
        IntentionOption.delete,
      ]);
      expect(items.map((item) => item.hint), everyElement(isNull));
      expect(items.last.tone, OptionRowTone.danger);
    },
  );

  test('пояснения архивирования используют состав предпросмотра', () {
    final child = testDetailsIntentionId(2);
    ArchiveCascadePreview preview(List<int> children, int relations) {
      final composition = ArchiveCascadeComposition(
        departing: children.map(testDetailsIntentionId).toList(),
        promoted: [],
        mainsLosingRelation: [],
        archivedRelationCount: relations,
      );
      return ArchiveCascadePreview(
        revision: revision,
        plan: CascadePlan(
          withSupporting: composition,
          onlyThis: composition,
          asksQuestion: children.isNotEmpty,
        ),
        titles: {child: 'Дочернее'},
      );
    }

    expect(
      intentionOptions(ru, _loaded(), statePreview: preview([2], 1))[1].hint,
      'Вместе с ним в архив уйдут вспомогательные намерения: 1',
    );
    expect(
      intentionOptions(ru, _loaded(), statePreview: preview([], 1))[1].hint,
      'Его связи архивируются вместе с ним',
    );
    expect(
      intentionOptions(ru, _loaded(), statePreview: preview([], 0))[1].hint,
      'Останется в сохранённых путях и не будет предлагаться в новых',
    );
  });

  test(
    'пояснения восстановления считают возвращаемые связи и вспомогательные',
    () {
      RestoreCascadePreview preview(int count, int relations) {
        final composition = RestoreCascadeComposition(
          restored: count == 0 ? [] : [testDetailsIntentionId(2)],
          returnedAsMain: null,
          restoredRelationCount: relations,
        );
        return RestoreCascadePreview(
          revision: revision,
          plan: CascadePlan(
            withSupporting: composition,
            onlyThis: composition,
            asksQuestion: count > 0,
          ),
          titles: const {},
        );
      }

      final loaded = _loaded(archived: true);
      expect(
        intentionOptions(ru, loaded, statePreview: preview(1, 1))[1].hint,
        'Вместе с ним вернутся вспомогательные намерения: 1',
      );
      expect(
        intentionOptions(ru, loaded, statePreview: preview(0, 1))[1].hint,
        'Его связи с активными намерениями восстановятся вместе с ним',
      );
      expect(
        intentionOptions(ru, loaded, statePreview: preview(0, 0))[1].hint,
        'Новые пути снова смогут его использовать',
      );
    },
  );

  test('удаление объясняет сохранённые пути или теги', () {
    final empty = givenCascadePreview(
      subject,
      CascadeOperation.delete,
      revision,
    ) as IntentionDeleteCascadePreview;
    final inPath = IntentionDeleteCascadePreview(
      revision: revision,
      plan: empty.plan,
      titles: const {},
      isInActionPath: true,
    );
    expect(
      intentionOptions(ru, _loaded(), deletePreview: empty)[2].hint,
      'Его теги сохранятся',
    );
    expect(
      intentionOptions(ru, _loaded(), deletePreview: inPath)[2].hint,
      'В сохранённых путях останется с пометкой «Удалено»',
    );
  });

  test('удаление называет уходящие и архивируемые намерения', () {
    final composition = DeleteCascadeComposition(
      departing: [testDetailsIntentionId(2)],
      promoted: [],
      archivedByInvariant: [testDetailsIntentionId(3)],
      mainsLosingRelation: [],
      deletedRelationCount: 1,
      archivedRelationCount: 1,
    );
    final preview = IntentionDeleteCascadePreview(
      revision: revision,
      plan: CascadePlan(
        withSupporting: composition,
        onlyThis: composition,
        asksQuestion: true,
      ),
      titles: const {},
      isInActionPath: true,
    );
    expect(
      intentionOptions(ru, _loaded(), deletePreview: preview)[2].hint,
      'Вместе с ним будут удалены вспомогательные намерения: 1; в архив уйдут намерения: 1',
    );
  });

  test('во время операции все пункты недоступны', () {
    final items = intentionOptions(ru, _loaded(running: true));
    expect(items.map((item) => item.value), everyElement(isNull));
    expect(
      items.map((item) => item.hint),
      everyElement('Дождитесь окончания текущего изменения'),
    );
  });

  test('«Изменить» ждёт снимок, а остальные пункты доступны', () {
    final items = intentionOptions(ru, _loaded(awaitingSnapshot: true));
    expect(items.first.value, isNull);
    expect(items[1].value, IntentionOption.archive);
    expect(items[2].value, IntentionOption.delete);
  });
}

IntentionDetailsLoaded _loaded({
  bool archived = false,
  bool running = false,
  bool awaitingSnapshot = false,
}) => IntentionDetailsLoaded(
  details: IntentionDetails(
    intention: testDetailsIntention(
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
    ),
    relationCounts: testRelationCounts(),
  ),
  revision: const TestDetailsRevision(0),
  isOperationRunning: running,
  isAwaitingConfirmedSnapshot: awaitingSnapshot,
);
