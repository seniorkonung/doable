import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/tag_color_picker.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
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

  for (final (locale, labels, title, group) in [
    (
      const Locale('ru'),
      [
        'Без цвета',
        'Коричневый',
        'Оранжевый',
        'Оливковый',
        'Зелёный',
        'Бирюзовый',
        'Синий',
        'Сиреневый',
        'Фиолетовый',
        'Розовый',
      ],
      'Цвет',
      'Цвет тега',
    ),
    (
      const Locale('en'),
      [
        'No color',
        'Brown',
        'Orange',
        'Olive',
        'Green',
        'Teal',
        'Blue',
        'Violet',
        'Purple',
        'Pink',
      ],
      'Color',
      'Tag color',
    ),
  ]) {
    testWidgets('новый тег показывает локализованный выбор и объявляет '
        'только смену предварительного цвета: ${locale.languageCode}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = _Repository();
      await _pumpEditor(tester, repository, locale: locale);

      expect(find.text(title), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(TagColorPicker)).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('tag-editor-name')))
              .dy,
        ),
      );
      expect(find.bySemanticsLabel(group), findsOneWidget);
      for (final label in labels) {
        expect(_swatch(label), findsOneWidget);
        expect(
          tester.getSemantics(_swatch(label)),
          isSemantics(
            label: label,
            isButton: true,
            hasSelectedState: true,
            isSelected: label == labels.first,
            hasTapAction: true,
          ),
        );
      }
      expect(
        tester.getSemantics(find.text(labels.first)),
        isSemantics(isLiveRegion: false),
      );
      expect(tester.takeAnnouncements(), isEmpty);
      final dot = find.descendant(
        of: find.byKey(const ValueKey('tag-editor-name')),
        matching: find.byType(TagDot),
      );
      expect(tester.getSize(dot), const Size.square(10));
      expect(
        tester.renderObject(dot),
        paints..circle(
          color: DoableColors.light.grip,
          style: PaintingStyle.stroke,
          strokeWidth: 1.5,
        ),
      );

      await tester.tap(_swatch(labels[6]));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(labels[6])),
        isSemantics(label: labels[6], isLiveRegion: true),
      );
      expect(
        tester.getSemantics(_swatch(labels[6])),
        isSemantics(
          label: labels[6],
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.renderObject(dot),
        paints..circle(color: DoableColors.light.tagBlue),
      );
      expect(tester.takeAnnouncements(), isEmpty);
      expect(repository.commands, isEmpty);
      await tester.tap(_swatch(labels[6]));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(labels[6])),
        isSemantics(label: labels[6], isLiveRegion: true),
      );
      expect(tester.takeAnnouncements(), isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'Дом',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('tag-editor-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      await tester.pump();
      expect(repository.commands.single, isA<CreateTag>());
      expect(_name(repository.commands.single), 'Дом');
      expect(_color(repository.commands.single), TagColor.blue);
      repository.fail(const TagUnavailableFailure());
      await tester.pumpAndSettle();
      expect(find.text(labels[6]), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final (originalColor, selectedColor, originalLabel, selectedLabel) in [
    (null, TagColor.blue, 'No color', 'Blue'),
    (TagColor.blue, null, 'Blue', 'No color'),
  ]) {
    testWidgets('правка только цвета с $originalLabel на $selectedLabel '
        'отправляет одно изменение с прежним названием', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _Repository();
      final original = Tag(
        id: _id(1),
        name: TagName.fromInput('Дом'),
        color: originalColor,
      );
      await _pumpEditor(
        tester,
        repository,
        editorContext: TagEditorRenaming(original),
      );

      expect(
        tester.getSemantics(find.text(originalLabel)),
        isSemantics(isLiveRegion: false),
      );
      expect(
        tester.getSemantics(_swatch(originalLabel)),
        isSemantics(
          label: originalLabel,
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(_swatch(selectedLabel));
      await tester.pumpAndSettle();
      expect(repository.commands, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('tag-editor-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      await tester.pump();
      final command = repository.commands.single as UpdateTag;
      expect(command.tagId, original.id);
      expect(command.name.value, 'Дом');
      expect(command.color, selectedColor);
      repository.fail(const TagUnavailableFailure());
      await tester.pumpAndSettle();
      expect(find.text(selectedLabel), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets(
    'конфликт названия сохраняет введённое название и зелёный выбор',
    (tester) async {
      final repository = _Repository();
      await _pumpEditor(
        tester,
        repository,
        editorContext: TagEditorRenaming(
          Tag(id: _id(1), name: TagName.fromInput('Дом'), color: TagColor.blue),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'работа',
      );
      await tester.tap(_swatch('Green'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('tag-editor-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      await tester.pump();
      final command = repository.commands.single as UpdateTag;
      expect(command.name.value, 'работа');
      expect(command.color, TagColor.green);
      repository.fail(TagNameOccupiedFailure(_id(2)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tag-editor-field-failure')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
            .controller!
            .text,
        'работа',
      );
      expect(find.text('Green'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('tag-editor-submit')),
            )
            .onPressed,
        isNull,
      );
      final dot = find.descendant(
        of: find.byKey(const ValueKey('tag-editor-name')),
        matching: find.byType(TagDot),
      );
      expect(
        tester.renderObject(dot),
        paints..circle(color: DoableColors.light.tagGreen),
      );
    },
  );

  testWidgets('отмена предварительного выбора не отправляет изменение тега', (
    tester,
  ) async {
    final repository = _Repository();
    final original = Tag(
      id: _id(1),
      name: TagName.fromInput('Дом'),
      color: TagColor.blue,
    );
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'Origin',
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Каталог')),
        ),
        AutoRoute(page: TagEditorRoute.page),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      router.push(TagEditorRoute(editorContext: TagEditorRenaming(original))),
    );
    await tester.pumpAndSettle();
    await tester.tap(_swatch('Green'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tag-editor-cancel')));
    await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Каталог'), findsOneWidget);
    expect(repository.commands, isEmpty);
    unawaited(
      router.push(TagEditorRoute(editorContext: TagEditorRenaming(original))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Blue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (locale, context, message, color) in [
    (
      const Locale('ru'),
      TagEditorCreating(TagCreationFormKey()),
      'Сохранение этого тега уже выполняется. Дождитесь результата.',
      null,
    ),
    (
      const Locale('en'),
      TagEditorRenaming(
        Tag(id: _id(1), name: TagName.fromInput('Home'), color: TagColor.blue),
      ),
      'Saving this tag is already in progress. Wait for its result.',
      TagColor.blue,
    ),
  ]) {
    testWidgets(
      'повторное сохранение сообщает о занятости, а после отказа отправляет '
      'новое название с цветом тега: ${locale.languageCode}',
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
        expect(repository.commands, hasLength(1));

        await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
        await tester.pump();
        expect(repository.commands.map(_name), ['Первое имя', 'Второе имя']);
        expect(repository.commands.map(_color), [color, color]);
        repository.fail(const TagUnavailableFailure());
        await tester.pumpAndSettle();
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

Future<void> _pumpEditor(
  WidgetTester tester,
  _Repository repository, {
  Locale locale = const Locale('en'),
  TagEditorContext? editorContext,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          // Android с TalkBack не поддерживает SemanticsService.sendAnnouncement.
          data: MediaQuery.of(context).copyWith(supportsAnnounce: false),
          child: child!,
        ),
        home: TagEditorPage(
          editorContext:
              editorContext ?? TagEditorCreating(TagCreationFormKey()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _swatch(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == label,
);

String _name(TagCommand command) => switch (command) {
  CreateTag(:final name) || UpdateTag(:final name) => name.value,
  _ => throw StateError('Форма отправила не команду сохранения тега'),
};

TagColor? _color(TagCommand command) => switch (command) {
  CreateTag(:final color) || UpdateTag(:final color) => color,
  _ => throw StateError('Форма отправила не команду сохранения тега'),
};

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
