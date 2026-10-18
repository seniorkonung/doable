import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_message_plan.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  late List<GraphPresentableCompletion> successes;
  late List<GraphPresentableCompletion> failures;

  setUpAll(() async {
    final repository = ControlledDetailsRepository();
    final container = ProviderContainer.test(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    successes = [];
    failures = [];
    try {
      for (final isFailure in [false, true]) {
        for (var index = 1; index <= 3; index++) {
          final intention = testDetailsIntention(index: index);
          final commandIndex = repository.commands.length;
          final accepted = coordinator.acceptExisting(
            DeleteIntention(intention.id),
            presentationTitle: intention.title,
          ) as IntentionCommandAccepted;
          repository.completeCommand(
            commandIndex,
            isFailure
                ? const ResultFailure(IntentionUnavailableFailure())
                : testDetailsDeletedResult(intention),
          );
          (isFailure ? failures : successes).add(await accepted.future);
        }
      }
    } finally {
      await coordinator.shutdown();
      container.dispose();
    }
  });

  test('выбирает самый ранний отказ раньше ожидающих успехов', () {
    final messages = {
      successes[0]: 'Первый отказ',
      failures[0]: 'Первый отказ',
      successes[1]: 'Последний успех',
      failures[1]: 'Другой отказ',
    };

    final plan = planGraphOperationMessage([
      successes[0],
      failures[0],
      successes[1],
      failures[1],
    ], (completion) => GraphOperationMessage(messages[completion]!));

    expect(plan.coveredTokens, [failures[0].token]);
    expect(plan.message.text, 'Первый отказ');
    expect(plan.otherCount, 0);
  });

  test(
    'объединяет несоседние отказы только по совпадению итогового текста',
    () {
      final messages = {
        failures[0]: 'Не удалось архивировать «Купить хлеб»',
        failures[1]: 'Не удалось архивировать «Оплатить счёт»',
        successes[0]: 'Успех',
        failures[2]: 'Не удалось архивировать «Купить хлеб»',
      };

      final plan = planGraphOperationMessage([
        failures[0],
        failures[1],
        successes[0],
        failures[2],
      ], (completion) => GraphOperationMessage(messages[completion]!));

      expect(plan.coveredTokens, [failures[0].token, failures[2].token]);
      expect(plan.message.text, 'Не удалось архивировать «Купить хлеб»');
      expect(plan.otherCount, 1);
    },
  );

  test('объединяет все успехи с текстом последнего результата', () {
    final messages = {
      successes[0]: 'Создано',
      successes[1]: 'Изменено',
      successes[2]: 'Архивировано',
    };

    final plan = planGraphOperationMessage(
      successes,
      (completion) => GraphOperationMessage(messages[completion]!),
    );

    expect(plan.coveredTokens, successes.map((completion) => completion.token));
    expect(plan.message.text, 'Архивировано');
    expect(plan.otherCount, 2);
  });

  for (final isFailure in [false, true]) {
    test(
      'одиночный ${isFailure ? 'отказ' : 'успех'} не имеет остальных результатов',
      () {
        final completion = (isFailure ? failures : successes).first;

        final plan = planGraphOperationMessage([
          completion,
        ], (_) => const GraphOperationMessage('Результат'));

        expect(plan.coveredTokens, [completion.token]);
        expect(plan.message.text, 'Результат');
        expect(plan.otherCount, 0);
      },
    );
  }

  test(
    'фиксирует состав и текст независимо от последующих изменений входа',
    () {
      final completions = [successes[0], successes[1]];
      var message = 'Показанный результат';

      final plan = planGraphOperationMessage(
        completions,
        (_) => GraphOperationMessage(message),
      );
      completions
        ..clear()
        ..add(failures[0]);
      message = 'Новый результат';

      expect(plan.coveredTokens, [successes[0].token, successes[1].token]);
      expect(plan.message.text, 'Показанный результат');
      expect(plan.otherCount, 1);
      expect(() => plan.coveredTokens.clear(), throwsUnsupportedError);
    },
  );
}
