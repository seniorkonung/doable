import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:doable/src/tag/presentation/editor/tag_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_positions.dart';

const _screen = Size(390, 844);
const _statusBar = 47.0;

void main() {
  for (final (locale, texts) in [
    (
      const Locale('ru'),
      (
        title: 'Новый тег',
        field: 'Название тега',
        color: 'Цвет',
        colors: 'Цвет тега',
        none: 'Без цвета',
        create: 'Создать тег',
        occupied: 'Тег с таким названием уже есть.',
      ),
    ),
    (
      const Locale('en'),
      (
        title: 'New tag',
        field: 'Tag name',
        color: 'Color',
        colors: 'Tag color',
        none: 'No color',
        create: 'Create tag',
        occupied: 'A tag with this name already exists.',
      ),
    ),
  ]) {
    testWidgets('${locale.languageCode}: лист «Новый тег» показывает '
        'предложенное название, «Без цвета» и доступную ошибку занятого '
        'названия', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpApp(tester, locale: locale);
      await h.open(initialName: 'парк', existingNames: ['Дом']);

      expect(find.text(texts.title), findsOne);
      expect(_nameText(tester), 'парк');
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.field)),
        isSemantics(isTextField: true, value: 'парк'),
      );
      expect(find.text(texts.color), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.colors)),
        isSemantics(label: texts.colors),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.none).last),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, texts.create)),
        isSemantics(isButton: true, isEnabled: true),
      );

      await tester.enterText(_nameField, '  дом ');
      await tester.pump();

      expect(
        tester.getSemantics(find.text(texts.occupied)),
        isSemantics(label: texts.occupied, isLiveRegion: true),
      );
      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, texts.create)),
        isSemantics(isButton: true, isEnabled: false),
      );
      semantics.dispose();
    });
  }

  testWidgets('Создание тега без выбора цвета', (tester) async {
    final h = await _pumpApp(tester);
    await h.open(initialName: 'Дом');

    await tester.tap(_create);
    await tester.pump();

    final create = h.repository.commands.single as CreateTag;
    expect((create.name.value, create.color), ('Дом', null));
    expect(h.accepted, hasLength(1));
    // Повторное нажатие во время записи не принимает вторую отправку.
    await tester.tap(find.text('Сохраняем тег…'));
    await tester.pump();
    expect(h.repository.commands, hasLength(1));

    h.repository.command.complete(TagCommandSucceeded(_created('Дом')));
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(h.isClosed, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('выбор цвета сразу меняет точку в поле и пишется только '
      'созданием', (tester) async {
    final h = await _pumpApp(tester);
    await h.open(initialName: 'Дом');
    expect(_nameDot(tester).color, isNull);

    await tester.tap(find.bySemanticsLabel('Синий').last);
    await tester.pump();

    expect(_nameDot(tester).color, DoableTagColor.blue);
    expect(h.repository.commands, isEmpty);

    await tester.tap(_create);
    await tester.pump();
    final create = h.repository.commands.single as CreateTag;
    expect(create.color, TagColor.blue);
  });

  testWidgets('отказ записи виден поверх листа над «Создать тег», а лист '
      'сохраняет название и цвет', (tester) async {
    final h = await _pumpApp(tester);
    await h.open(initialName: 'Дом');
    await tester.enterText(_nameField, 'Дом и сад');
    await tester.tap(find.bySemanticsLabel('Синий').last);
    await tester.tap(_create);
    await tester.pump();

    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    final message = find.descendant(
      of: find.byType(Sheet),
      matching: find.byType(SnackBar),
    );
    expect(message, findsOne);
    expect(
      tester.getRect(message).bottom,
      lessThanOrEqualTo(tester.getRect(_create).top),
    );
    expect(_nameText(tester), 'Дом и сад');
    expect(_nameDot(tester).color, DoableTagColor.blue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('при открытой клавиатуре поле «Название» и «Создать тег» '
      'видны', (tester) async {
    final h = await _pumpApp(tester);
    await h.open(initialName: 'Дом');
    await tester.showKeyboard(_nameField);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    const aboveKeyboard = 844.0 - keyboard;
    final sheet = tester.getRect(find.byType(Sheet));
    final field = tester.getRect(_nameField);
    final create = tester.getRect(_create);
    expect(field.top, greaterThan(sheet.top));
    expect(create.top, greaterThan(field.bottom));
    expect(create.bottom, lessThanOrEqualTo(aboveKeyboard));
    expect(tester.takeException(), isNull);
  });
}

final _nameField = find.descendant(
  of: find.byType(Sheet),
  matching: find.byType(TextField),
);

final _create = find.byType(FilledButton);

String _nameText(WidgetTester tester) =>
    tester.widget<TextField>(_nameField).controller!.text;

TagDot _nameDot(WidgetTester tester) => tester.widget<TagDot>(
  find.descendant(of: _nameField, matching: find.byType(TagDot)),
);

final class _Harness {
  _Harness(this._tester, this.repository);

  final WidgetTester _tester;
  final TagCatalogTestRepository repository;

  /// Создания, которые лист отдал вызывающему.
  final accepted = <TagCommandAccepted>[];

  /// Последний показанный лист закрыт.
  var isClosed = false;

  late TagEditorCreating _creating;

  Future<void> open({
    required String initialName,
    List<String> existingNames = const [],
  }) async {
    isClosed = false;
    _creating = TagEditorCreating(
      TagCreationFormKey(),
      initialName: initialName,
      existingNames: [
        for (final name in existingNames) TagName.fromInput(name),
      ],
      onCreationAccepted: accepted.add,
    );
    await _tester.tap(find.text('Открыть'));
    await _tester.pumpAndSettle();
  }
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen
    ..padding = const FakeViewPadding(top: _statusBar)
    ..viewPadding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
  // Общая поверхность показывает сообщения только в активном приложении.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final repository = TagCatalogTestRepository();
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  final harness = _Harness(tester, repository);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showTagSheet(
                  context,
                  harness._creating,
                ).whenComplete(() => harness.isClosed = true),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return harness;
}

ConfirmedGraphResult<TagCommandSuccess> _created(String name) =>
    ConfirmedGraphResult(
      revision: const TagCatalogTestRevision(2),
      value: TagCreated(
        TagCreatedChange(
          revision: const TagCatalogTestRevision(2),
          after: Tag(
            id: (TagId.decode(
              '00000000-0000-4000-8000-000000000001',
            ) as TagIdDecodingSuccess).id,
            name: TagName.fromInput(name),
            color: null,
            position: tagPositionAt(1),
          ),
        ),
      ),
    );
