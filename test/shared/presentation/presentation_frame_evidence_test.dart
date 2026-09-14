import 'package:doable/src/shared/presentation/presentation_frame_evidence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('подтверждает сообщение после первого видимого кадра один раз', (
    tester,
  ) async {
    final subject = Object();
    final presented = <Object>[];

    await tester.pumpWidget(
      _app(
        PresentationFrameEvidence<Object>(
          subject: subject,
          onPresented: presented.add,
          child: const Text('Ошибка'),
        ),
      ),
    );
    expect(presented, [same(subject)]);

    await tester.pumpAndSettle();
    await tester.pump();
    expect(presented, [same(subject)]);
  });

  testWidgets('не подтверждает сообщение вне видимой области до прокрутки', (
    tester,
  ) async {
    final subject = Object();
    final presented = <Object>[];

    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 2000),
              PresentationFrameEvidence<Object>(
                subject: subject,
                onPresented: presented.add,
                child: const Text('Ошибка'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(presented, isEmpty);

    await tester.ensureVisible(find.text('Ошибка'));
    await tester.pumpAndSettle();
    expect(presented, [same(subject)]);
  });

  testWidgets('не подтверждает ошибку под диалогом до его закрытия', (
    tester,
  ) async {
    final subject = ValueNotifier<Object?>(null);
    addTearDown(subject.dispose);
    final presented = <Object>[];

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('Диалог')),
                ),
                child: const Text('Открыть'),
              ),
              ValueListenableBuilder<Object?>(
                valueListenable: subject,
                builder: (context, value, _) =>
                    PresentationFrameEvidence<Object>(
                      subject: value,
                      onPresented: presented.add,
                      child: const Text('Ошибка'),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    final failure = Object();
    subject.value = failure;
    await tester.pumpAndSettle();
    expect(presented, isEmpty);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Диалог'), findsNothing);
    expect(presented, [same(failure)]);
  });

  for (final scenario in <({String name, Widget Function(Widget) hide})>[
    (name: 'Offstage', hide: (child) => Offstage(child: child)),
    (
      name: 'нулевой прозрачности',
      hide: (child) => Opacity(opacity: 0, child: child),
    ),
    (
      name: 'нулевой высоты отсечения',
      hide: (child) => ClipRect(child: Align(heightFactor: 0, child: child)),
    ),
  ]) {
    testWidgets('не подтверждает сообщение внутри ${scenario.name}', (
      tester,
    ) async {
      final presented = <Object>[];

      await tester.pumpWidget(
        _app(
          scenario.hide(
            PresentationFrameEvidence<Object>(
              subject: Object(),
              onPresented: presented.add,
              child: const Text('Ошибка'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(presented, isEmpty);
    });
  }

  for (final scenario
      in <
        ({
          AppLifecycleState state,
          List<AppLifecycleState> away,
          List<AppLifecycleState> back,
        })
      >[
        (
          state: AppLifecycleState.inactive,
          away: [AppLifecycleState.inactive],
          back: [AppLifecycleState.resumed],
        ),
        (
          state: AppLifecycleState.hidden,
          away: [AppLifecycleState.inactive, AppLifecycleState.hidden],
          back: [AppLifecycleState.inactive, AppLifecycleState.resumed],
        ),
        (
          state: AppLifecycleState.paused,
          away: [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ],
          back: [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ],
        ),
        (
          state: AppLifecycleState.detached,
          away: [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.detached,
          ],
          back: [AppLifecycleState.resumed],
        ),
      ]) {
    testWidgets(
      '${scenario.state.name} не разрешает подтверждение до возвращения в resumed',
      (tester) async {
        final subject = Object();
        final presented = <Object>[];
        for (final state in scenario.away) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }

        await tester.pumpWidget(
          _app(
            PresentationFrameEvidence<Object>(
              subject: subject,
              onPresented: presented.add,
              child: const Text('Ошибка'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(presented, isEmpty);

        for (final state in scenario.back) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        expect(tester.binding.hasScheduledFrame, isTrue);
        await tester.pump();
        expect(presented, [same(subject)]);
      },
    );
  }

  testWidgets(
    'неизвестное исходное lifecycle state не разрешает подтверждение',
    (tester) async {
      tester.binding.resetInternalState();
      expect(tester.binding.lifecycleState, isNull);
      final subject = Object();
      final presented = <Object>[];

      await tester.pumpWidget(
        _app(
          PresentationFrameEvidence<Object>(
            subject: subject,
            onPresented: presented.add,
            child: const Text('Ошибка'),
          ),
        ),
      );
      await tester.pump();
      expect(presented, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(presented, [same(subject)]);
    },
  );

  testWidgets('новый результат подтверждается отдельно от прежнего', (
    tester,
  ) async {
    final subject = ValueNotifier<Object?>(Object());
    addTearDown(subject.dispose);
    final presented = <Object>[];

    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<Object?>(
          valueListenable: subject,
          builder: (context, value, _) => PresentationFrameEvidence<Object>(
            subject: value,
            onPresented: presented.add,
            child: const Text('Ошибка'),
          ),
        ),
      ),
    );
    final first = subject.value!;

    subject.value = null;
    await tester.pump();
    final retryFailure = Object();
    subject.value = retryFailure;
    await tester.pump();

    expect(presented, [same(first), same(retryFailure)]);
  });

  testWidgets('callback освобождённого виджета бездействует', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final presented = <Object>[];

    await tester.pumpWidget(
      _app(
        PresentationFrameEvidence<Object>(
          subject: Object(),
          onPresented: presented.add,
          child: const Text('Ошибка'),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(_app(const SizedBox.shrink()));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(presented, isEmpty);
  });
}

Widget _app(Widget body) => MaterialApp(home: Scaffold(body: body));
