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
        editTitle: 'Изменить тег',
        save: 'Сохранить',
        blue: 'Синий',
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
        editTitle: 'Edit tag',
        save: 'Save',
        blue: 'Blue',
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

    testWidgets('${locale.languageCode}: лист «Изменить тег» показывает '
        'сохранённые название и цвет, а «Сохранить» недоступна до '
        'изменения', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpApp(tester, locale: locale);
      await h.openEditing(_tag('Дом', color: TagColor.blue));

      expect(find.text(texts.editTitle), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.field)),
        isSemantics(isTextField: true, value: 'Дом'),
      );
      expect(_nameDot(tester).color, DoableTagColor.blue);
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.blue).last),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, texts.save)),
        isSemantics(isButton: true, isEnabled: false),
      );
      semantics.dispose();
    });
  }

  testWidgets('«Сохранить» доступна после смены только цвета, а '
      'подтверждённое изменение закрывает лист без сообщения', (tester) async {
    final h = await _pumpApp(tester);
    final tag = _tag('Дом', color: TagColor.blue);
    await h.openEditing(tag, existingNames: ['Дом', 'Работа']);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);

    await tester.tap(find.bySemanticsLabel('Без цвета').last);
    await tester.pump();
    await tester.tap(_submit);
    await tester.pump();

    final update = h.repository.commands.single as UpdateTag;
    expect(
      (update.tagId, update.name.value, update.color),
      (tag.id, 'Дом', null),
    );
    h.repository.command.complete(
      TagCommandSucceeded(_updated(tag, _tag('Дом'))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(h.isClosed, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Конфликт названия не сохраняет выбранный цвет', (tester) async {
    final h = await _pumpApp(tester);
    await h.openEditing(
      _tag('Дом', color: TagColor.blue),
      existingNames: ['Дом', 'Работа'],
    );

    await tester.enterText(_nameField, 'работа');
    await tester.tap(find.bySemanticsLabel('Зелёный').last);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(Sheet),
        matching: find.text('Тег с таким названием уже есть.'),
      ),
      findsOne,
    );
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    await tester.tap(_submit);
    await tester.pump();
    expect(h.repository.commands, isEmpty);
    expect(_nameText(tester), 'работа');
    expect(_nameDot(tester).color, DoableTagColor.green);
  });

  testWidgets('Слишком длинное переименование', (tester) async {
    final h = await _pumpApp(tester);
    await h.openEditing(_tag('Дом'), existingNames: ['Дом']);
    final longName = '🙂' * 256;

    await tester.enterText(_nameField, longName);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(Sheet),
        matching: find.text(
          lookupAppLocalizations(const Locale('ru')).tagNameTooLong,
        ),
      ),
      findsOne,
    );
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(_nameText(tester), longName);
    expect(h.repository.commands, isEmpty);
  });

  for (final (way, close) in <(String, Future<void> Function(WidgetTester))>[
    (
      'свайпом вниз',
      (tester) =>
          tester.fling(find.text('Изменить тег'), const Offset(0, 600), 2000),
    ),
    ('касанием затемнения', (tester) => tester.tapAt(const Offset(195, 80))),
    ('системным «назад»', (tester) => tester.binding.handlePopRoute()),
  ]) {
    testWidgets('Закрытие листа без сохранения не меняет тег: $way', (
      tester,
    ) async {
      final h = await _pumpApp(tester);
      await h.openEditing(
        _tag('Дом', color: TagColor.blue),
        existingNames: ['Дом'],
      );
      await tester.enterText(_nameField, 'Быт');
      await tester.tap(find.bySemanticsLabel('Зелёный').last);
      await tester.pump();

      await close(tester);
      await tester.pumpAndSettle();

      expect(find.byType(Sheet), findsNothing);
      expect(h.isClosed, isTrue);
      expect(h.repository.commands, isEmpty);
    });
  }

  testWidgets('Выбор цвета доступен экранному диктору', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await _pumpApp(tester);
    await h.openEditing(_tag('Дом'), existingNames: ['Дом']);
    final current = find.descendant(
      of: find.byType(Sheet),
      matching: find.text('Синий'),
    );
    expect(current, findsNothing);

    await tester.tap(find.bySemanticsLabel('Синий').last);
    await tester.pump();

    expect(
      tester.getSemantics(current),
      isSemantics(label: 'Синий', isLiveRegion: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Синий').last),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Без цвета').last),
      isSemantics(isButton: true, isSelected: false),
    );
    semantics.dispose();
  });

  testWidgets('отказ записи изменения виден поверх листа над «Сохранить», а '
      'лист сохраняет название и цвет', (tester) async {
    final h = await _pumpApp(tester);
    await h.openEditing(_tag('Дом'), existingNames: ['Дом']);
    await tester.enterText(_nameField, 'Быт');
    await tester.tap(find.bySemanticsLabel('Синий').last);
    await tester.pump();
    await tester.tap(_submit);
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
      lessThanOrEqualTo(tester.getRect(_submit).top),
    );
    expect(_nameText(tester), 'Быт');
    expect(_nameDot(tester).color, DoableTagColor.blue);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
  });

  testWidgets('Создание тега без выбора цвета', (tester) async {
    final h = await _pumpApp(tester);
    await h.open(initialName: 'Дом');

    await tester.tap(_submit);
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

  testWidgets('лист копии показывает предложенные название и цвет и '
      'создаёт копию с размещением после исходного тега', (tester) async {
    final h = await _pumpApp(tester);
    final source = _tag('Дом', color: TagColor.blue);
    await h.open(
      initialName: 'Дом 2',
      initialColor: TagColor.blue,
      placement: AfterTagPlacement(source.id),
      existingNames: ['Дом'],
    );

    expect(find.text('Новый тег'), findsOne);
    expect(_nameText(tester), 'Дом 2');
    expect(_nameDot(tester).color, DoableTagColor.blue);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);

    await tester.tap(_submit);
    await tester.pump();
    final create = h.repository.commands.single as CreateTag;
    expect((create.name.value, create.color), ('Дом 2', TagColor.blue));
    expect((create.placement as AfterTagPlacement).tagId, source.id);
  });

  testWidgets('слишком длинное название показывает причину, делает «Создать '
      'тег» недоступной и остаётся для исправления', (tester) async {
    final h = await _pumpApp(tester);
    await h.open(initialName: 'Дом');
    final longName = '🙂' * 256;

    await tester.enterText(_nameField, longName);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(Sheet),
        matching: find.text(
          lookupAppLocalizations(const Locale('ru')).tagNameTooLong,
        ),
      ),
      findsOne,
    );
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(_nameText(tester), longName);
    expect(h.repository.commands, isEmpty);
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

    await tester.tap(_submit);
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
    await tester.tap(_submit);
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
      lessThanOrEqualTo(tester.getRect(_submit).top),
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
    final create = tester.getRect(_submit);
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

final _submit = find.byType(FilledButton);

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

  late TagEditorContext _editing;

  Future<void> open({
    required String initialName,
    TagColor? initialColor,
    TagPlacement placement = TagPlacement.first,
    List<String> existingNames = const [],
  }) async {
    await _open(
      TagEditorCreating(
        TagCreationFormKey(),
        initialName: initialName,
        initialColor: initialColor,
        placement: placement,
        existingNames: [
          for (final name in existingNames) TagName.fromInput(name),
        ],
        onCreationAccepted: accepted.add,
      ),
    );
  }

  Future<void> openEditing(Tag tag, {List<String> existingNames = const []}) =>
      _open(
        TagEditorRenaming(
          tag,
          existingNames: [
            for (final name in existingNames) TagName.fromInput(name),
          ],
        ),
      );

  Future<void> _open(TagEditorContext editing) async {
    isClosed = false;
    _editing = editing;
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
                  harness._editing,
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

Tag _tag(String name, {TagColor? color}) => Tag(
  id: (TagId.decode(
    '00000000-0000-4000-8000-000000000001',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(1),
);

ConfirmedGraphResult<TagCommandSuccess> _created(String name) =>
    ConfirmedGraphResult(
      revision: const TagCatalogTestRevision(2),
      value: TagCreated(
        TagCreatedChange(
          revision: const TagCatalogTestRevision(2),
          after: _tag(name),
        ),
      ),
    );

ConfirmedGraphResult<TagCommandSuccess> _updated(Tag before, Tag after) =>
    ConfirmedGraphResult(
      revision: const TagCatalogTestRevision(2),
      value: TagUpdated(
        TagUpdatedChange(
          revision: const TagCatalogTestRevision(2),
          before: before,
          after: after,
        ),
      ),
    );
