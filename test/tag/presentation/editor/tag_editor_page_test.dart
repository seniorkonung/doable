import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('ошибка длины читаема и сохраняет ввод при увеличенном тексте', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repository();
    await _pumpEditor(tester, repository, largeText: true);
    final longName = '🙂' * 256;
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      longName,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('tag-editor-submit')));
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    await tester.pump();

    expect(find.textContaining('255 visible characters'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
          .controller!
          .text,
      longName,
    );
    expect(repository.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('исчезновение ошибки до кадра освобождает право оболочке', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpEditor(tester, repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagEditorPage)),
    );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final registration = coordinator.registerAppPresentation();
    addTearDown(registration.release);
    GraphAppPresentationClaim? fallback;
    unawaited(registration.nextClaim().then((claim) => fallback = claim));

    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Дом',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    repository.fail(TagNameOccupiedFailure(_id(1)));
    await tester.pump();
    await tester.pump();
    final renderer = tester.widget<OperationFailurePresentation>(
      find.byType(OperationFailurePresentation),
    );
    expect(renderer.claim, isNotNull);
    expect(fallback, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Быт',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(OperationFailurePresentation), findsNothing);
    expect(fallback?.token, same(renderer.claim!.token));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('закрытие формы до кадра возвращает ошибку оболочке', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpEditor(tester, repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagEditorPage)),
    );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final registration = coordinator.registerAppPresentation();
    addTearDown(registration.release);
    GraphAppPresentationClaim? fallback;
    unawaited(registration.nextClaim().then((claim) => fallback = claim));

    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Дом',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    repository.fail(TagNameOccupiedFailure(_id(1)));
    await tester.pump();
    await tester.pump();
    final claim = tester
        .widget<OperationFailurePresentation>(
          find.byType(OperationFailurePresentation),
        )
        .claim!;
    expect(fallback, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(fallback?.token, same(claim.token));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'после доступного кадра исчезновение ошибки не выдаёт её повторно',
    (tester) async {
      final repository = _Repository();
      await _pumpEditor(tester, repository);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagEditorPage)),
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final registration = coordinator.registerAppPresentation();
      addTearDown(registration.release);
      GraphAppPresentationClaim? fallback;
      unawaited(registration.nextClaim().then((claim) => fallback = claim));

      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'Дом',
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      repository.fail(TagNameOccupiedFailure(_id(1)));
      await tester.pumpAndSettle();
      final renderer = tester.widget<OperationFailurePresentation>(
        find.byType(OperationFailurePresentation),
      );
      expect(renderer.claim, isNotNull);
      expect(coordinator.claimInitiatorFailure(renderer.claim!.token), isNull);

      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'Быт',
      );
      await tester.pumpAndSettle();
      expect(find.byType(OperationFailurePresentation), findsNothing);
      expect(fallback, isNull);
    },
  );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _Repository repository, {
  bool largeText = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(largeText ? 2.5 : 1)),
          child: child!,
        ),
        home: TagEditorPage(
          editorContext: TagEditorCreating(TagCreationFormKey()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

final class _Repository extends Fake implements PersonalGraphRepository {
  final commands = <TagCommand>[];
  Completer<TagCommandResult>? pending;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command as TagCommand);
    final request = Completer<TagCommandResult>();
    pending = request;
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void fail(TagCommandFailure failure) =>
      pending!.complete(TagCommandFailed(failure));
}
