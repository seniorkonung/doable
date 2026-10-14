import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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

  for (final (locale, context, message) in [
    (
      const Locale('ru'),
      TagEditorCreating(TagCreationFormKey()),
      'Сохранение этого тега уже выполняется. Дождитесь результата.',
    ),
    (
      const Locale('en'),
      TagEditorRenaming(Tag(id: _id(1), name: TagName.fromInput('Home'))),
      'Saving this tag is already in progress. Wait for its result.',
    ),
  ]) {
    testWidgets(
      'повторное сохранение сообщает о занятости: ${locale.languageCode}',
      (tester) async {
        final repository = _Repository();
        final container = ProviderContainer(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final coordinator = container.read(
          graphCommandCoordinatorProvider.notifier,
        );
        final registration = coordinator.registerAppPresentation();
        addTearDown(registration.release);
        final firstClaim = registration.nextClaim();

        Widget host(Widget home) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        );

        await tester.pumpWidget(host(TagEditorPage(editorContext: context)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'Первое имя',
        );
        await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
        await tester.pump();
        expect(repository.commands, hasLength(1));

        await tester.pumpWidget(host(const SizedBox.shrink()));
        await tester.pumpWidget(host(TagEditorPage(editorContext: context)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'Второе имя',
        );
        await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
        await tester.pump();

        final notice = find.text(message);
        expect(notice, findsOneWidget);
        expect(
          tester.getSemantics(notice),
          isSemantics(label: message, isLiveRegion: true),
        );
        expect(repository.commands, hasLength(1));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
              .controller!
              .text,
          'Второе имя',
        );

        repository.fail(const TagUnavailableFailure());
        await tester.pumpAndSettle();
        // Оболочка показывает отказ первой отправки и подтверждает показ.
        final claim = (await firstClaim)!;
        expect(claim.completions.single.isFailure, isTrue);
        coordinator.confirmAppPresentation(
          claim,
          claim.completions.map((completion) => completion.token),
        );
        await tester.pump();
        expect(notice, findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('tag-editor-submit')),
              )
              .onPressed,
          isNotNull,
        );
        expect(repository.commands, hasLength(1));
      },
    );
  }

  testWidgets('ошибка длины читаема и сохраняет ввод', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repository();
    await _pumpEditor(tester, repository);
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
    expect(fallback, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(fallback, isNotNull);
    expect(
      fallback!.completions.single,
      isA<TagCommandCompletion>().having(
        (completion) => completion.confirmedResult,
        'результат',
        isA<TagCommandFailed>().having(
          (result) => result.failure,
          'ошибка',
          isA<TagNameOccupiedFailure>(),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

Future<void> _pumpEditor(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
