import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/text_field.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../details/details_test_support.dart';

void main() {
  // Общая поверхность показывает сообщения только в активном приложении.
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final (locale, texts) in [
    (const Locale('ru'), (title: 'Изменить намерение', save: 'Сохранить')),
    (const Locale('en'), (title: 'Edit intention', save: 'Save')),
  ]) {
    testWidgets('открывается без панели с сохранёнными текстами, курсором в '
        'конце названия и недоступной «Сохранить»: ${locale.languageCode}', (
      tester,
    ) async {
      final intention = testDetailsIntention(
        title: 'Бегать',
        description: 'Утром в парке',
      );
      await _openEditPage(
        tester,
        ControlledDetailsRepository(),
        intention,
        locale: locale,
      );

      expect(find.byType(AppNavigationBar), findsNothing);
      final bar = tester.widget<TopBar>(find.byType(TopBar));
      expect(bar.title, texts.title);
      expect(
        find.descendant(
          of: find.byType(TopBar),
          matching: find.text(texts.save),
        ),
        findsOneWidget,
      );
      expect(_saveButton(tester).onPressed, isNull);
      expect(_controller(tester, _titleField).text, 'Бегать');
      expect(_controller(tester, _descriptionField).text, 'Утром в парке');
      final title = tester.widget<EditableText>(
        find.descendant(of: _titleField, matching: find.byType(EditableText)),
      );
      expect(title.focusNode.hasFocus, isTrue);
      expect(
        title.controller.selection,
        const TextSelection.collapsed(offset: 'Бегать'.length),
      );
    });
  }

  testWidgets('отсутствующее описание открывается пустым полем', (
    tester,
  ) async {
    final intention = testDetailsIntention(description: null);
    await _openEditPage(tester, ControlledDetailsRepository(), intention);

    expect(_controller(tester, _descriptionField).text, isEmpty);
    expect(find.text('Добавить описание'), findsOneWidget);
  });

  testWidgets('название из пробелов закрывает «Сохранить» при изменённом '
      'описании', (tester) async {
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, ControlledDetailsRepository(), intention);

    await tester.enterText(_descriptionField, 'Новое описание');
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);
    await tester.enterText(_titleField, '   ');
    await tester.pump();

    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('успех закрывает экран, а шапка страницы показывает новое '
      'название без сообщения', (tester) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(title: 'Бегать');
    final saved = testDetailsIntention(title: 'Бегать по утрам');
    await _openEditPage(tester, repository, before);

    await tester.enterText(_titleField, saved.title);
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    expect(
      repository.commands.single,
      isA<UpdateIntention>()
          .having((command) => command.title, 'название', saved.title)
          .having(
            (command) => command.description,
            'описание',
            before.description,
          ),
    );
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    // Подтверждённое изменение перечитывает подробные данные страницы.
    await waitForDetailRequests(repository, 2);
    repository.detailRequests.last.add(ResultSuccess(saved));
    await tester.pumpAndSettle();

    expect(find.byType(IntentionEditPage), findsNothing);
    expect(tester.widget<PageHead>(find.byType(PageHead)).name, saved.title);
    await tester.pump(const Duration(seconds: 5));
    expect(_operationMessage, findsNothing);
  });

  testWidgets('слишком длинное название объясняется у поля, а общая '
      'поверхность отказ не повторяет', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, repository, intention);
    final entered = 'я' * 256;

    await tester.enterText(_titleField, entered);
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    repository.completeCommand(
      0,
      const ResultFailure(
        IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.tooLong,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _titleField,
        matching: find.text('Используйте не более 255 символов.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Notice), findsNothing);
    expect(find.byType(IntentionEditPage), findsOneWidget);
    expect(_controller(tester, _titleField).text, entered);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_operationMessage, findsNothing);
  });

  testWidgets('отказ хранилища показан над полями, ввод сохранён, а повторное '
      '«Сохранить» закрывает экран', (tester) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(title: 'Бегать');
    final saved = testDetailsIntention(title: 'Бегать по утрам');
    await _openEditPage(tester, repository, before);

    await tester.enterText(_titleField, saved.title);
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Notice),
        matching: find.text(
          'Не удалось сохранить изменения. Повторите попытку.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byType(Notice)).bottom,
      lessThanOrEqualTo(tester.getRect(_titleField).top),
    );
    expect(_controller(tester, _titleField).text, saved.title);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_operationMessage, findsNothing);

    await tester.tap(_save);
    await tester.pump();
    expect(repository.commands, hasLength(2));
    repository.completeCommand(
      1,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IntentionEditPage), findsNothing);
  });

  testWidgets('текст не меняется, пока сохранение выполняется', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, repository, intention);

    await tester.enterText(_titleField, 'Бегать по утрам');
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    await tester.enterText(_titleField, 'Плавать');
    await tester.pump();

    expect(_controller(tester, _titleField).text, 'Бегать по утрам');
  });

  testWidgets('клавиша ввода в названии оставляет его прежним и переводит '
      'фокус в описание', (tester) async {
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, ControlledDetailsRepository(), intention);

    // Клавиша ввода экранной клавиатуры выполняет действие, которое поле
    // объявило подключению ввода.
    final keyboardAction = tester.testTextInput.setClientArgs!['inputAction'];
    await tester.testTextInput.receiveAction(
      TextInputAction.values.firstWhere(
        (action) => action.toString() == keyboardAction,
      ),
    );
    await tester.pump();

    expect(_controller(tester, _titleField).text, 'Бегать');
    expect(_saveButton(tester).onPressed, isNull);
    final description = tester.widget<EditableText>(
      find.descendant(
        of: _descriptionField,
        matching: find.byType(EditableText),
      ),
    );
    expect(description.focusNode.hasFocus, isTrue);
  });

  testWidgets('описание растёт до тринадцати строк и дальше прокручивается '
      'внутри поля', (tester) async {
    final intention = testDetailsIntention(description: null);
    await _openEditPage(tester, ControlledDetailsRepository(), intention);

    await tester.enterText(
      _descriptionField,
      List.filled(13, 'строка').join('\n'),
    );
    await tester.pump();
    expect(_descriptionScroll(tester).maxScrollExtent, 0);

    await tester.enterText(
      _descriptionField,
      List.filled(14, 'строка').join('\n'),
    );
    await tester.pump();
    expect(_descriptionScroll(tester).maxScrollExtent, greaterThan(0));
  });

  testWidgets('при тексте масштаба 2 и открытой клавиатуре поля и '
      '«Сохранить» доступны без переполнения', (tester) async {
    addTearDown(tester.view.reset);
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, repository, intention, textScale: 2);
    // Клавиатура занимает половину экрана.
    tester.view.viewInsets = FakeViewPadding(
      bottom: tester.view.physicalSize.height / 2,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      _descriptionField,
      List.filled(20, 'длинная строка описания').join('\n'),
    );
    await tester.pumpAndSettle();
    for (final field in [_titleField, _descriptionField]) {
      // Поле описания выше видимой части: проверяется его начало.
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(field.hitTestable(at: Alignment.topCenter), findsOneWidget);
    }
    expect(_save.hitTestable(), findsOneWidget);
    await tester.tap(_save);
    await tester.pump();

    expect(repository.commands.single, isA<UpdateIntention>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('отказ хранилища на прокрученном экране снимает фокус с полей '
      'и прокручивает к сообщению над полями без общей поверхности', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, repository, intention, textScale: 2);
    final description = await _scrollPastStartWithDescription(tester);

    await tester.tap(_save);
    await tester.pump();
    // Поля только для чтения закрывают клавиатуру на время сохранения.
    expect(tester.testTextInput.hasAnyClients, isFalse);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    // Без фокуса клавиатура не возвращается и не уводит сообщение.
    for (final field in [_titleField, _descriptionField]) {
      expect(_editable(tester, field).focusNode.hasFocus, isFalse);
    }
    expect(tester.testTextInput.hasAnyClients, isFalse);
    const message = 'Не удалось сохранить изменения. Повторите попытку.';
    expect(find.byType(Notice).hitTestable(), findsOneWidget);
    expect(find.bySemanticsLabel(message), findsOneWidget);
    semantics.dispose();
    expect(_controller(tester, _titleField).text, 'Бегать');
    expect(_controller(tester, _descriptionField).text, description);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_operationMessage, findsNothing);
  });

  testWidgets('отказ длины названия на прокрученном экране прокручивает к '
      'объяснению под полем названия', (tester) async {
    addTearDown(tester.view.reset);
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, repository, intention, textScale: 2);
    final entered = 'я' * 256;
    await tester.enterText(_titleField, entered);
    await tester.pump();
    await _scrollPastStartWithDescription(tester);

    await tester.tap(_save);
    await tester.pump();
    repository.completeCommand(
      0,
      const ResultFailure(
        IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.tooLong,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find
          .descendant(
            of: _titleField,
            matching: find.text('Используйте не более 255 символов.'),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(_controller(tester, _titleField).text, entered);
  });

  for (final (way, leave) in <(String, Future<void> Function(WidgetTester))>[
    ('стрелка', (tester) => tester.tap(_back)),
    ('системное «назад»', (tester) => tester.binding.handlePopRoute()),
  ]) {
    testWidgets('$way закрывает экран без вопроса, пока текст не изменён', (
      tester,
    ) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(title: 'Бегать');
      await _openEditPage(tester, repository, intention);

      await leave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(IntentionEditPage), findsNothing);
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(_discardQuestion, findsNothing);
      expect(repository.commands, isEmpty);
    });
  }

  for (final (answer, respond)
      in <(String, Future<void> Function(WidgetTester))>[
        (
          '«Продолжить правку»',
          (tester) => tester.tap(find.text('Продолжить правку')),
        ),
        ('нажатие на подложку', (tester) => tester.tapAt(const Offset(5, 5))),
        ('«назад» над вопросом', (tester) => tester.binding.handlePopRoute()),
      ]) {
    testWidgets('изменённый текст вызывает вопрос, а $answer возвращает к '
        'полям с прежним текстом', (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(title: 'Бегать');
      await _openEditPage(tester, repository, intention);
      await tester.enterText(_titleField, 'Бегать по утрам');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_discardQuestion, findsOneWidget);
      expect(find.text('Изменения намерения не сохранятся.'), findsOneWidget);
      await respond(tester);
      await tester.pumpAndSettle();

      expect(_discardQuestion, findsNothing);
      expect(find.byType(IntentionEditPage), findsOneWidget);
      expect(_controller(tester, _titleField).text, 'Бегать по утрам');
      expect(_saveButton(tester).onPressed, isNotNull);
      expect(repository.commands, isEmpty);
    });
  }

  testWidgets('вопрос об отмене изменений переведён на английский', (
    tester,
  ) async {
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(
      tester,
      ControlledDetailsRepository(),
      intention,
      locale: const Locale('en'),
    );
    await tester.enterText(_titleField, 'Бегать по утрам');
    await tester.pump();

    await tester.tap(_back);
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(
      find.text('Your changes to the intention won’t be saved.'),
      findsOneWidget,
    );
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
  });

  testWidgets('«Отменить» после изменения описания закрывает экран, а '
      'страница показывает прежнее описание', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      title: 'Бегать',
      description: 'Утром в парке',
    );
    await _openEditPage(tester, repository, intention);
    await tester.enterText(_descriptionField, 'Вечером на стадионе');
    await tester.pump();

    await tester.tap(_back);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(find.byType(IntentionEditPage), findsNothing);
    expect(find.text('Утром в парке'), findsOneWidget);
    expect(find.text('Вечером на стадионе'), findsNothing);
    expect(repository.commands, isEmpty);
  });

  testWidgets('уход стрелкой во время сохранения закрывает экран без '
      'вопроса, а успех даёт новые данные на странице без сообщения', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(title: 'Бегать');
    final saved = testDetailsIntention(title: 'Бегать по утрам');
    await _openEditPage(tester, repository, before);
    await tester.enterText(_titleField, saved.title);
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();

    await tester.tap(_back);
    await tester.pump();
    // Страница показывает индикатор занятости, и кадры не успокаиваются.
    await tester.pump(const Duration(seconds: 1));
    expect(_discardQuestion, findsNothing);
    expect(find.byType(IntentionEditPage), findsNothing);
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests.last.add(ResultSuccess(saved));
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(1));
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(tester.widget<PageHead>(find.byType(PageHead)).name, saved.title);
    expect(_operationMessage, findsNothing);
  });

  testWidgets('отказ сохранения после ухода стрелкой показан одним '
      'сообщением общей поверхности над страницей намерения', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, repository, intention);
    await tester.enterText(_titleField, 'Бегать по утрам');
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();

    await tester.tap(_back);
    await tester.pump();
    // Страница показывает индикатор занятости, и кадры не успокаиваются.
    await tester.pump(const Duration(seconds: 1));
    expect(_discardQuestion, findsNothing);
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(1));
    expect(_operationMessage, findsOneWidget);
    expect(find.byType(IntentionEditPage), findsNothing);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(tester.widget<PageHead>(find.byType(PageHead)).name, 'Бегать');
  });

  testWidgets('смена системной темы сохраняет экран и начатое изменение', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final intention = testDetailsIntention(title: 'Бегать');
    await _openEditPage(tester, ControlledDetailsRepository(), intention);
    await tester.enterText(_titleField, 'Бегать по утрам');
    await tester.pump();

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    final page = find.byType(IntentionEditPage);
    expect(page, findsOneWidget);
    expect(Theme.of(tester.element(page)).brightness, Brightness.dark);
    expect(_controller(tester, _titleField).text, 'Бегать по утрам');
    expect(_saveButton(tester).onPressed, isNotNull);
  });
}

final _titleField = find.byKey(const ValueKey('intention-edit-title'));
final _descriptionField = find.byKey(
  const ValueKey('intention-edit-description'),
);
final _save = find.descendant(
  of: find.byType(TopBar),
  matching: find.byType(Button),
);
final _back = find.descendant(
  of: find.byType(TopBar),
  matching: find.byType(DoableIcon),
);
final _discardQuestion = find.text('Отменить изменения?');
final _operationMessage = find.byKey(const ValueKey('graph-operation-message'));

Button _saveButton(WidgetTester tester) => tester.widget<Button>(_save);

TextEditingController _controller(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller;

EditableText _editable(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

ScrollPosition _descriptionScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _descriptionField, matching: find.byType(Scrollable)),
    )
    .position;

/// Открывает клавиатуру и вводит длинное описание, после чего начало экрана
/// уходит из видимой части. Возвращает введённое описание.
Future<String> _scrollPastStartWithDescription(WidgetTester tester) async {
  // Клавиатура занимает половину экрана.
  tester.view.viewInsets = FakeViewPadding(
    bottom: tester.view.physicalSize.height / 2,
  );
  await tester.pumpAndSettle();
  final description = List.filled(20, 'длинная строка описания').join('\n');
  await tester.enterText(_descriptionField, description);
  await tester.pumpAndSettle();
  expect(_titleField.hitTestable(at: Alignment.topCenter), findsNothing);
  return description;
}

/// Открывает экран изменения над страницей намерения с полученными данными,
/// как это делает вход в правку.
Future<void> _openEditPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  Intention intention, {
  Locale locale = const Locale('ru'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: OrdinaryPageTestApp(
        locale: locale,
        routes: [AutoRoute(page: IntentionEditRoute.page)],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: GraphOperationPresenter(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: IntentionDetailsPage(intentionId: intention.id),
      ),
    ),
  );
  await tester.pump();
  await waitForDetailRequests(repository, 1);
  repository.detailRequests.single.add(ResultSuccess(intention));
  await tester.pumpAndSettle();
  unawaited(
    tester
        .element(find.byType(IntentionDetailsPage))
        .router
        .push(IntentionEditRoute(intentionId: intention.id)),
  );
  await tester.pumpAndSettle();
}
