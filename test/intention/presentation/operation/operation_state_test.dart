import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OperationState исчерпывающе различает четыре состояния', () {
    const states = <OperationState<int>>[
      OperationIdle<int>(),
      OperationRunning<int>(),
      OperationSucceeded<int>(42),
      OperationFailed<int>(IntentionUnavailableFailure()),
    ];

    final descriptions = states.map(
      (state) => switch (state) {
        OperationIdle<int>() => 'idle',
        OperationRunning<int>() => 'running',
        OperationSucceeded<int>(:final value) => 'succeeded:$value',
        OperationFailed<int>(:final failure) => 'failed:${failure.code.name}',
      },
    );

    expect(descriptions, [
      'idle',
      'running',
      'succeeded:42',
      'failed:unavailable',
    ]);
  });
}
