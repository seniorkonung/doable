import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_shell_page.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../catalog/catalog_test_support.dart';

/// Доступность полного сценария нижней панели создания намерения: экранный
/// диктор, клавиатура и guidelines Android на русском и английском.
///
/// Геометрия на тесных экранах с клавиатурой и увеличенным текстом
/// проверяется в `intention_creation_sheet_layout_test.dart`.
void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'экранный диктор проходит компактную панель в порядке чтения при любой ориентации, клавиатуре и заполнении черновика — $code',
      (tester) async {
        final semantics = tester.ensureSemantics();
        _usePhone(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        final sessions = _EditorSessions();
        await _openCatalog(tester, _repositoryWithTags(), sessions, locale);
        await tester.tap(find.byKey(_catalogCreate));
        await tester.pumpAndSettle();

        for (final tags in [
          <Tag>[],
          [_home, _work],
        ]) {
          for (final tag in tags) {
            sessions.notifier(tester).draftTagSet.add(tag);
          }
          for (final (size, keyboard) in [
            (_phone, 0.0),
            (_phone, 280.0),
            (Size(_phone.height, _phone.width), 0.0),
            (Size(_phone.height, _phone.width), 180.0),
          ]) {
            _usePhone(tester, size: size, keyboard: keyboard);
            await tester.pumpAndSettle();
            expect(
              _traversal(tester),
              _panel(l10n, tags: [for (final tag in tags) tag.name.value]),
              reason: '$size, клавиатура $keyboard, тегов: ${tags.length}',
            );
            _expectNoSizeActions();
          }
        }
        semantics.dispose();
      },
    );

    testWidgets(
      'экранный диктор без жестов открывает панель, готовит все пять полей черновика через общий выбор тегов и объяснение готовности и возвращается в ту же панель — $code',
      (tester) async {
        final semantics = tester.ensureSemantics();
        _usePhone(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        final sessions = _EditorSessions();
        final repository = _repositoryWithTags();
        final router = await _openCatalog(tester, repository, sessions, locale);

        // «+» без видимой надписи объясняет действие подсказкой.
        final create = find.byKey(_catalogCreate);
        expect(
          find.descendant(of: create, matching: find.byType(Text)),
          findsNothing,
        );
        expect(
          tester.getSemantics(create),
          isSemantics(
            tooltip: l10n.editorCreateAction,
            isButton: true,
            hasTapAction: true,
          ),
        );
        tester.semantics.tap(_nodeOf(tester, create));
        await tester.pumpAndSettle();

        // Панель называет себя заголовком, фокус ввода — в названии, а
        // каталог и основная навигация под ней экранному диктору недоступны.
        expect(router.current.name, IntentionEditorRoute.name);
        final session = sessions.single;
        expect(_isFocusedIn(tester, find.byKey(_title)), isTrue);
        expect(
          tester.getSemantics(find.byKey(_heading)),
          isSemantics(
            label: l10n.editorTitle,
            isHeader: true,
            namesRoute: true,
          ),
        );
        expect(_traversal(tester), _panel(l10n));
        _expectOption(
          tester,
          _favorite,
          label: l10n.editorFavoriteOption,
          tooltip: l10n.editorFavoriteOptionOff,
          isOn: false,
          icon: Icons.star_border,
        );
        _expectOption(
          tester,
          _readiness,
          label: l10n.editorReadinessOption,
          tooltip: l10n.editorReadinessOptionOff,
          isOn: false,
          icon: Icons.check_circle_outline,
        );

        // Пользовательский текст объявляется как введён, без перевода.
        await tester.enterText(find.byKey(_title), _userTitle);
        await tester.enterText(find.byKey(_description), _userDescription);
        await tester.pumpAndSettle();
        _expectNoSizeActions();
        expect(
          find.semantics.byLabel(l10n.editorTitleLabel).evaluate().single,
          isSemantics(value: _userTitle, isTextField: true, isMultiline: true),
        );
        expect(
          find.semantics.byLabel(l10n.editorDescriptionLabel).evaluate().single,
          isSemantics(
            value: _userDescription,
            isTextField: true,
            isMultiline: true,
          ),
        );

        // Общий выбор тегов закрывает панель от диктора и фокуса, а теги
        // добавляются в черновик явными действиями.
        tester.semantics.tap(_byTooltip(l10n.editorChooseTags));
        await tester.pumpAndSettle();
        expect(router.current.name, TagCatalogRoute.name);
        expect(_traversal(tester), contains(l10n.tagCatalogSelectionTitle));
        expect(_traversal(tester), isNot(contains(l10n.editorTitleLabel)));
        expect(_isFocusedIn(tester, find.byType(IntentionEditorPage)), isFalse);
        for (final tag in _tags) {
          final name = tag.name.value;
          tester.semantics.tap(
            find.semantics.byLabel(
              '$name\n${l10n.tagCatalogAvailableForDraft}',
            ),
          );
          await tester.pump();
          tester.semantics.tap(
            find.semantics.byLabel(l10n.tagCatalogAddToDraftNamed(name)),
          );
          await tester.pump();
          expect(
            find.semantics.byLabel('$name\n${l10n.tagCatalogInDraft}'),
            findsOne,
          );
        }
        tester.semantics.tap(_nodeOf(tester, find.byType(BackButton)));
        await tester.pumpAndSettle();

        // Возврат раскрывает ту же панель с прежним фокусом и выбранными
        // тегами, которые снимаются из черновика.
        expect(router.current.name, IntentionEditorRoute.name);
        _expectSameSession(sessions, session);
        expect(_isFocusedIn(tester, find.byKey(_description)), isTrue);
        expect(_traversal(tester), _panel(l10n, tags: ['Дом', 'Работа']));
        _expectNoSizeActions();

        tester.semantics.tap(_nodeOf(tester, find.byKey(_favorite)));
        await tester.pumpAndSettle();
        _expectOption(
          tester,
          _favorite,
          label: l10n.editorFavoriteOption,
          tooltip: l10n.editorFavoriteOptionOn,
          isOn: true,
          icon: Icons.star,
        );

        // Объяснение готовности — верхняя поверхность: диктор слышит оба
        // критерия, а фокус остаётся в объяснении до ответа.
        tester.semantics.tap(_nodeOf(tester, find.byKey(_readiness)));
        await tester.pumpAndSettle();
        final readinessDialog = _readinessDialog(tester, l10n);
        expect(_traversal(tester), readinessDialog);
        expect(_isFocusInRouteOf(tester, find.byType(AlertDialog)), isTrue);
        tester.semantics.tap(
          find.semantics.byLabel(l10n.editorReadinessCancelAction),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(_isFocusedIn(tester, find.byKey(_description)), isTrue);
        expect(
          sessions.state(tester).draft.readiness,
          IntentionReadiness.notReady,
        );

        tester.semantics.tap(_nodeOf(tester, find.byKey(_readiness)));
        await tester.pumpAndSettle();
        expect(_traversal(tester), readinessDialog);
        tester.semantics.tap(
          find.semantics.byLabel(l10n.editorReadinessConfirmAction),
        );
        await tester.pumpAndSettle();
        expect(_isFocusedIn(tester, find.byKey(_description)), isTrue);
        _expectOption(
          tester,
          _readiness,
          label: l10n.editorReadinessOption,
          tooltip: l10n.editorReadinessOptionOn,
          isOn: true,
          icon: Icons.check_circle,
        );

        tester.semantics.tap(_byTooltip(l10n.editorRemoveDraftTag('Работа')));
        await tester.pumpAndSettle();
        expect(_traversal(tester), _panel(l10n, tags: ['Дом']));

        final draft = sessions.state(tester).draft;
        expect(draft.title, _userTitle);
        expect(draft.description, _userDescription);
        expect(draft.tagIds, [_home.id]);
        expect(draft.favoriteMark, FavoriteMark.favorite);
        expect(draft.readiness, IntentionReadiness.ready);
        _expectSameSession(sessions, session);
        expect(repository.commands, isEmpty);
        expect(repository.tagCommands, isEmpty);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      'экранный диктор без жестов слышит подтверждение закрытия, ход сохранения, ошибки и исправление, а черновик и фокус остаются в панели до успеха — $code',
      (tester) async {
        final semantics = tester.ensureSemantics();
        _usePhone(tester);
        final l10n = await AppLocalizations.delegate.load(locale);
        final sessions = _EditorSessions();
        final repository = _repositoryWithTags();
        final router = await _openCatalog(tester, repository, sessions, locale);
        await tester.tap(find.byKey(_catalogCreate));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_title), '   ');
        await tester.enterText(find.byKey(_description), _userDescription);
        sessions.notifier(tester)
          ..draftTagSet.add(_home)
          ..draftTagSet.add(_work)
          ..markFavorite()
          ..confirmReadiness();
        await tester.pumpAndSettle();
        final tags = ['Дом', 'Работа'];

        // Модальный фон и кнопка закрытия ведут к одному подтверждению с
        // объяснением потери данных; продолжение возвращает фокус в панель.
        for (final close in [
          () => tester.semantics.dismiss(
            find.semantics.byLabel(l10n.editorCloseFormAction),
          ),
          () => tester.semantics.tap(_byTooltip(l10n.editorCloseFormAction)),
        ]) {
          close();
          await tester.pumpAndSettle();
          expect(_traversal(tester), [
            _barrierLabel(tester),
            l10n.editorCloseDiscardTitle,
            l10n.editorCloseDiscardMessage,
            l10n.editorCloseContinueAction,
            l10n.editorCloseDiscardAction,
          ]);
          expect(_isFocusInRouteOf(tester, find.byType(AlertDialog)), isTrue);
          tester.semantics.tap(
            find.semantics.byLabel(l10n.editorCloseContinueAction),
          );
          await tester.pumpAndSettle();
          expect(router.current.name, IntentionEditorRoute.name);
          expect(_isFocusedIn(tester, find.byKey(_description)), isTrue);
          expect(_traversal(tester), _panel(l10n, tags: tags));
        }

        // Во время сохранения диктор слышит его ход, правки недоступны, а
        // закрытие остаётся доступным.
        tester.semantics.tap(find.semantics.byLabel(l10n.editorSaveAction));
        await tester.pump();
        expect(repository.commands, hasLength(1));
        expect(
          tester.getSemantics(find.byKey(_submit)),
          isSemantics(
            label: l10n.editorSaving,
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
        );
        for (final control in [
          _favorite,
          _readiness,
          _chooseTags,
          _tagRemove(_home),
        ]) {
          expect(
            tester.getSemantics(find.byKey(control)),
            isSemantics(
              hasEnabledState: true,
              isEnabled: false,
              hasTapAction: false,
            ),
            reason: '$control',
          );
        }
        expect(
          tester.getSemantics(find.byKey(_closeButton)),
          isSemantics(
            tooltip: l10n.editorCloseFormAction,
            isEnabled: true,
            hasTapAction: true,
          ),
        );

        // Ошибка названия объявляется сразу после своего поля.
        repository.completeCommand(
          0,
          const ResultFailure(
            IntentionTextInputValidationFailure(
              IntentionTextValidationFailure(
                field: IntentionTextField.title,
                reason: IntentionTextValidationReason.empty,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final titleIndex = _traversal(tester).indexOf(l10n.editorTitleLabel);
        expect(
          _traversal(tester)[titleIndex + 1],
          l10n.editorTitleEmpty,
          reason: 'ошибка названия следует за полем',
        );
        expect(
          find.semantics.byPredicate(
            (node) =>
                node.label == l10n.editorTitleEmpty &&
                node.flagsCollection.isLiveRegion,
          ),
          findsOne,
        );
        expect(_isFocusedIn(tester, find.byKey(_description)), isTrue);
        expect(
          tester.getSemantics(find.byKey(_submit)),
          isSemantics(label: l10n.editorSaveAction, isEnabled: false),
        );
        await tester.enterText(find.byKey(_title), _userTitle);
        await tester.pumpAndSettle();
        expect(_traversal(tester), _panel(l10n, tags: tags));

        // Удалённый тег назван в своём элементе, а исправление объявлено
        // рядом с сообщением и сохранением.
        tester.semantics.tap(find.semantics.byLabel(l10n.editorSaveAction));
        await tester.pump();
        repository.completeCommand(
          1,
          ResultFailure(IntentionCreationTagsMissingFailure([_home.id])),
        );
        await tester.pumpAndSettle();
        final missingMessage = l10n.editorCreateTagsMissing(1);
        final removeMissing = l10n.editorRemoveMissingTags(1);
        final withMissingTag = _panel(l10n, tags: tags);
        withMissingTag[withMissingTag.indexOf('Дом')] =
            'Дом\n${l10n.editorDraftTagMissing}';
        withMissingTag.insertAll(withMissingTag.length - 1, [
          missingMessage,
          removeMissing,
        ]);
        expect(_traversal(tester), withMissingTag);
        expect(
          tester.getSemantics(find.byKey(_failure)),
          isSemantics(label: missingMessage, isLiveRegion: true),
        );
        tester.semantics.tap(find.semantics.byLabel(removeMissing));
        await tester.pumpAndSettle();
        expect(_traversal(tester), _panel(l10n, tags: ['Работа']));
        expect(repository.commands, hasLength(2));

        // Устранимый отказ предлагает повтор тем же действием.
        tester.semantics.tap(find.semantics.byLabel(l10n.editorSaveAction));
        await tester.pump();
        repository.completeCommand(
          2,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.byKey(_failure)),
          isSemantics(label: l10n.editorCreateUnavailable, isLiveRegion: true),
        );
        expect(
          tester.getSemantics(find.byKey(_submit)),
          isSemantics(
            label: l10n.commonRetry,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.commands, hasLength(4));
        expect(
          repository.commands.last,
          isA<CreateIntention>()
              .having((command) => command.title, 'название', _userTitle)
              .having(
                (command) => command.description,
                'описание',
                _userDescription,
              )
              .having((command) => command.tagIds, 'теги', [_work.id])
              .having(
                (command) => command.favoriteMark,
                'избранное',
                FavoriteMark.favorite,
              )
              .having(
                (command) => command.readiness,
                'готовность',
                IntentionReadiness.ready,
              ),
        );

        // Успех закрывает панель, и каталог с навигацией снова доступны.
        repository.completeCommand(3, _savedResult());
        await tester.pump();
        await tester.pump();
        _completeCatalogRefresh(repository);
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);
        expect(
          find.semantics.byPredicate(
            (node) =>
                node.label.contains(l10n.editorCreated) &&
                node.flagsCollection.isLiveRegion,
          ),
          findsWidgets,
        );
        expect(
          _traversal(tester),
          containsAll([l10n.editorCreateAction, l10n.catalogFilterLabel]),
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      'клавиатура открывает панель, проходит её по порядку, выполняет все действия и держит фокус в верхней поверхности при диалогах и выборе тегов — $code',
      (tester) async {
        _usePhone(tester);
        final sessions = _EditorSessions();
        final repository = _repositoryWithTags();
        final router = await _openCatalog(tester, repository, sessions, locale);

        await _tabTo(tester, find.byKey(_catalogCreate));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_isFocusedIn(tester, find.byKey(_title)), isTrue);
        await tester.enterText(find.byKey(_title), _userTitle);
        await tester.pumpAndSettle();

        // Действие экранной клавиатуры ведёт из растущего названия в
        // описание, сохраняя точный текст без дополнительных переносов.
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        expect(_isFocusedIn(tester, find.byKey(_description)), isTrue);
        expect(sessions.state(tester).draft.title, _userTitle);
        await tester.tap(find.byKey(_title));
        await tester.pumpAndSettle();

        // Порядок обхода совпадает с порядком чтения и замыкается в панели.
        expect(await _tabOrder(tester, steps: 8), [
          _description,
          _chooseTags,
          _favorite,
          _readiness,
          _submit,
          _closeButton,
          _title,
          _description,
        ]);
        expect(await _tabOrder(tester, steps: 2, backward: true), [
          _title,
          _closeButton,
        ]);

        // Отметки переключаются пробелом и вводом.
        await _tabTo(tester, find.byKey(_favorite));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(
          sessions.state(tester).draft.favoriteMark,
          FavoriteMark.favorite,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          sessions.state(tester).draft.favoriteMark,
          FavoriteMark.notFavorite,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(_isFocusedIn(tester, find.byKey(_favorite)), isTrue);

        // Объяснение готовности удерживает обход в себе; Escape закрывает
        // его без включения, а фокус возвращается к отметке.
        await _tabTo(tester, find.byKey(_readiness));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(_readinessConfirmation), findsOneWidget);
        expect(await _tabOrder(tester, steps: 3), [
          _readinessCancel,
          _readinessConfirm,
          _readinessCancel,
        ]);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(_readinessConfirmation), findsNothing);
        expect(
          sessions.state(tester).draft.readiness,
          IntentionReadiness.notReady,
        );
        expect(_isFocusedIn(tester, find.byKey(_readiness)), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await _tabTo(
          tester,
          find.byKey(_readinessConfirm),
          within: find.byType(AlertDialog),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          sessions.state(tester).draft.readiness,
          IntentionReadiness.ready,
        );
        expect(_isFocusedIn(tester, find.byKey(_readiness)), isTrue);

        // Общий выбор тегов принимает фокус целиком и возвращает его к
        // действию выбора в той же панели.
        await _tabTo(tester, find.byKey(_chooseTags));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(router.current.name, TagCatalogRoute.name);
        final selector = find.byType(TagCatalogPage);
        await _tabTo(tester, find.byKey(_tagRow(_home)), within: selector);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await _tabTo(tester, find.byKey(_addToDraft), within: selector);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await _tabTo(tester, find.byType(BackButton), within: selector);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_isFocusedIn(tester, find.byKey(_chooseTags)), isTrue);
        expect(sessions.state(tester).draft.tagIds, [_home.id]);

        // Снятие тега оставляет фокус в панели.
        await _tabTo(tester, find.byKey(_tagRemove(_home)));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(sessions.state(tester).draft.tagIds, isEmpty);
        expect(_isFocusedIn(tester, find.byType(IntentionEditorPage)), isTrue);

        // Подтверждение закрытия удерживает обход; Escape продолжает ввод.
        await _tabTo(tester, find.byKey(_closeButton));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);
        expect(await _tabOrder(tester, steps: 3), [
          _closeContinue,
          _closeDiscard,
          _closeContinue,
        ]);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_isFocusedIn(tester, find.byKey(_closeButton)), isTrue);

        // Сохранение вводом отправляет весь черновик одной командой.
        await _tabTo(tester, find.byKey(_submit));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          repository.commands.single,
          isA<CreateIntention>()
              .having((command) => command.title, 'название', _userTitle)
              .having((command) => command.tagIds, 'теги', isEmpty)
              .having(
                (command) => command.favoriteMark,
                'избранное',
                FavoriteMark.favorite,
              )
              .having(
                (command) => command.readiness,
                'готовность',
                IntentionReadiness.ready,
              ),
        );
        expect(_isFocusedIn(tester, find.byType(IntentionEditorPage)), isTrue);
        expect(sessions.added, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    for (final (textScale, size) in [
      (1.0, _phone),
      // Увеличенный текст на экране, где все поля и сообщения видны целиком:
      // частично прокрученные элементы guidelines оценили бы по обрезанной
      // части. Тесные экраны проверяет тест раскладки панели.
      (2.0, const Size(600, 1000)),
    ]) {
      testWidgets(
        'цели нажатия, подписи и контраст панели, её диалогов, хода сохранения и отказов проходят guidelines Android при масштабе текста ${(textScale * 100).round()}% — $code',
        (tester) async {
          final semantics = tester.ensureSemantics();
          _usePhone(tester, size: size);
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final sessions = _EditorSessions();
          final repository = _repositoryWithTags();
          await _openCatalog(tester, repository, sessions, locale);
          await tester.tap(find.byKey(_catalogCreate));
          await tester.pumpAndSettle();
          await _expectGuidelines(tester, 'пустая панель');

          await tester.enterText(find.byKey(_title), _userTitle);
          await tester.enterText(find.byKey(_description), _userDescription);
          sessions.notifier(tester)
            ..draftTagSet.add(_home)
            ..draftTagSet.add(_work)
            ..markFavorite()
            ..confirmReadiness();
          await tester.pumpAndSettle();
          await _expectGuidelines(tester, 'заполненная компактная панель');

          sessions.notifier(tester).disableReadiness();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_readiness));
          await tester.pumpAndSettle();
          await _expectGuidelines(tester, 'объяснение готовности');
          await tester.tap(find.byKey(_readinessConfirm));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(_closeButton));
          await tester.pumpAndSettle();
          await _expectGuidelines(tester, 'подтверждение закрытия');
          await tester.tap(find.byKey(_closeContinue));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(_submit));
          await tester.pump();
          await _expectGuidelines(tester, 'ход сохранения');
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
          await _expectGuidelines(tester, 'ошибка названия');

          await tester.enterText(find.byKey(_title), '$_userTitle!');
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_submit));
          await tester.pump();
          repository.completeCommand(
            1,
            ResultFailure(IntentionCreationTagsMissingFailure([_home.id])),
          );
          await tester.pumpAndSettle();
          await _expectGuidelines(tester, 'удалённый тег и исправление');

          await tester.tap(find.byKey(_removeMissing));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_submit));
          await tester.pump();
          repository.completeCommand(
            2,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          await _expectGuidelines(tester, 'повтор после устранимого отказа');
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}

const _catalogCreate = ValueKey('catalog-create-intention');
const _heading = ValueKey('intention-editor-heading');
const _title = ValueKey('intention-editor-title');
const _description = ValueKey('intention-editor-description');
const _chooseTags = ValueKey('intention-editor-choose-tags');
const _favorite = ValueKey('intention-editor-favorite');
const _readiness = ValueKey('intention-editor-readiness');
const _submit = ValueKey('intention-editor-submit');
const _failure = ValueKey('intention-editor-failure');
const _removeMissing = ValueKey('intention-editor-remove-missing-tags');
const _closeButton = ValueKey('intention-editor-close');
const _readinessConfirmation = ValueKey(
  'intention-editor-readiness-confirmation',
);
const _readinessCancel = ValueKey('intention-editor-readiness-cancel');
const _readinessConfirm = ValueKey('intention-editor-readiness-confirm');
const _closeConfirmation = ValueKey('intention-editor-close-confirmation');
const _closeContinue = ValueKey('intention-editor-close-continue');
const _closeDiscard = ValueKey('intention-editor-close-discard');
const _addToDraft = ValueKey('tag-catalog-add-to-draft');

ValueKey<String> _tagRemove(Tag tag) =>
    ValueKey('intention-editor-tag-remove-${tag.id.toCanonicalString()}');

ValueKey<String> _tagRow(Tag tag) =>
    ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}');

/// Пользовательские данные: интерфейс показывает их без перевода на любом
/// языке.
const _userTitle = 'Купить хлеб 🍞, молоко и продукты для ужина после работы';
const _userDescription = 'Зайти после работы\nWholegrain bread';

final _home = _tag(1, 'Дом');
final _work = _tag(2, 'Работа');
final _tags = [_home, _work];

/// Экран телефона в портретной ориентации.
const _phone = Size(360, 740);

/// Ставит экран [size] со строкой состояния и жестовой навигацией;
/// открытая клавиатура высотой [keyboard] закрывает нижний безопасный
/// отступ.
void _usePhone(WidgetTester tester, {Size size = _phone, double keyboard = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: 24, bottom: keyboard > 0 ? 0 : 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

/// Что экранный диктор объявляет по порядку обхода компактной панели с
/// выбранными тегами [tags]: модальный фон, закрытие, заголовок,
/// поля, теги со снятием, быстрые действия и сохранение.
List<String> _panel(AppLocalizations l10n, {List<String> tags = const []}) => [
  l10n.editorCloseFormAction,
  l10n.editorCloseFormAction,
  l10n.editorTitle,
  l10n.editorTitleLabel,
  l10n.editorDescriptionLabel,
  for (final tag in tags) ...[tag, l10n.editorRemoveDraftTag(tag)],
  l10n.editorChooseTags,
  l10n.editorFavoriteOption,
  l10n.editorReadinessOption,
  l10n.editorSaveAction,
];

/// Что экранный диктор объявляет в объяснении готовности: оба критерия
/// действия и ответы.
List<String> _readinessDialog(WidgetTester tester, AppLocalizations l10n) => [
  _barrierLabel(tester),
  l10n.editorReadinessConfirmationTitle,
  l10n.editorReadinessOneDayCriterion,
  l10n.editorReadinessClarityCriterion,
  l10n.editorReadinessCancelAction,
  l10n.editorReadinessConfirmAction,
];

/// Доступное название модального фона диалога.
String _barrierLabel(WidgetTester tester) =>
    MaterialLocalizations.of(tester.element(find.byType(AlertDialog)))
        .modalBarrierDismissLabel;

/// Названия узлов в порядке обхода экранным диктором: подпись, а у кнопки
/// со значком — подсказка.
List<String> _traversal(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    switch (node.getSemanticsData()) {
      SemanticsData(:final label) when label.isNotEmpty => label,
      SemanticsData(:final tooltip) => tooltip,
    },
];

/// Старые действия отсутствуют в тексте, подсказках и всём семантическом
/// дереве, включая названия и подсказки дополнительных действий диктора.
/// https://api.flutter.dev/flutter/semantics/SemanticsData/customSemanticsActionIds.html
void _expectNoSizeActions() {
  for (final label in const [
    'Развернуть форму',
    'Свернуть форму',
    'Expand the form',
    'Collapse the form',
  ]) {
    expect(find.text(label), findsNothing);
    expect(find.byTooltip(label), findsNothing);
    expect(
      find.semantics.byPredicate((node) {
        final data = node.getSemanticsData();
        final descriptions = [data.label, data.hint, data.tooltip];
        for (final id in data.customSemanticsActionIds ?? const <int>[]) {
          if (CustomSemanticsAction.getAction(id) case final action?) {
            descriptions.addAll([action.label ?? '', action.hint ?? '']);
          }
        }
        return descriptions.any((text) => text.contains(label));
      }, describeMatch: (_) => 'действие изменения размера «$label»'),
      findsNothing,
    );
  }
  expect(
    find.semantics.byAnyAction([
      SemanticsAction.increase,
      SemanticsAction.decrease,
    ]),
    findsNothing,
  );
}

/// Узел экранного диктора, которым объявлен виджет [finder].
FinderBase<SemanticsNode> _nodeOf(WidgetTester tester, Finder finder) {
  final id = tester.getSemantics(finder).id;
  return find.semantics.byPredicate(
    (node) => node.id == id,
    describeMatch: (_) => 'узел $finder',
  );
}

FinderBase<SemanticsNode> _byTooltip(String tooltip) =>
    find.semantics.byPredicate(
      (node) => node.tooltip == tooltip,
      describeMatch: (_) => 'узел с подсказкой «$tooltip»',
    );

/// Быстрая отметка объявляет назначение и включённость, а включённое
/// состояние отличается формой значка и текстом подсказки, а не только
/// цветом.
void _expectOption(
  WidgetTester tester,
  Key option, {
  required String label,
  required String tooltip,
  required bool isOn,
  required IconData icon,
}) {
  expect(
    tester.getSemantics(find.byKey(option)),
    isSemantics(
      label: label,
      isButton: true,
      hasToggledState: true,
      isToggled: isOn,
      hasEnabledState: true,
      isEnabled: true,
      hasTapAction: true,
    ),
  );
  expect(
    find.descendant(of: find.byKey(option), matching: find.byIcon(icon)),
    findsOneWidget,
  );
  expect(
    tester
        .widget<Tooltip>(
          find
              .ancestor(of: find.byKey(option), matching: find.byType(Tooltip))
              .first,
        )
        .message,
    tooltip,
  );
}

/// Основной фокус ввода находится в [finder] или в его потомке.
bool _isFocusedIn(WidgetTester tester, Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null || finder.evaluate().isEmpty) {
    return false;
  }
  final target = tester.element(finder);
  if (identical(focused, target)) {
    return true;
  }
  var isInside = false;
  focused.visitAncestorElements((element) {
    isInside = identical(element, target);
    return !isInside;
  });
  return isInside;
}

/// Основной фокус ввода принадлежит маршруту, в котором показан [finder]:
/// верхней поверхности, а не странице под ней.
bool _isFocusInRouteOf(WidgetTester tester, Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      identical(ModalRoute.of(focused), ModalRoute.of(tester.element(finder)));
}

/// Элементы панели и её диалогов, между которыми ходит фокус клавиатуры.
const _focusTargets = [
  _title,
  _description,
  _chooseTags,
  _favorite,
  _readiness,
  _submit,
  _closeButton,
  _readinessCancel,
  _readinessConfirm,
  _closeContinue,
  _closeDiscard,
];

/// Элементы, которые получают фокус за [steps] нажатий Tab или Shift+Tab.
Future<List<Key?>> _tabOrder(
  WidgetTester tester, {
  required int steps,
  bool backward = false,
}) async {
  final order = <Key?>[];
  for (var step = 0; step < steps; step++) {
    await _pressTab(tester, backward: backward);
    order.add(
      _focusTargets
          .where((key) => _isFocusedIn(tester, find.byKey(key)))
          .firstOrNull,
    );
  }
  return order;
}

/// Переводит фокус клавишей Tab к [target]. Каталог и основная навигация
/// под панелью не получают фокус; при [within] фокус не покидает его.
Future<void> _tabTo(
  WidgetTester tester,
  Finder target, {
  Finder? within,
}) async {
  for (var step = 0; step < 40; step++) {
    await _pressTab(tester);
    if (within != null) {
      expect(_isFocusedIn(tester, within), isTrue, reason: 'шаг обхода $step');
    }
    if (_isFocusedIn(tester, target)) {
      return;
    }
  }
  fail('Фокус не дошёл до $target');
}

Future<void> _pressTab(WidgetTester tester, {bool backward = false}) async {
  if (backward) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (backward) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  }
  await tester.pump();
  if (find.byType(IntentionEditorPage).evaluate().isNotEmpty) {
    expect(
      _isFocusedIn(tester, find.byType(AppShellPage)),
      isFalse,
      reason: 'фокус не уходит под панель',
    );
  }
}

/// Действующие guidelines Android: размер целей нажатия, их подписи и
/// контраст текста.
Future<void> _expectGuidelines(WidgetTester tester, String state) async {
  for (final guideline in [
    androidTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ]) {
    final evaluation = await guideline.evaluate(tester);
    expect(evaluation.passed, isTrue, reason: '$state: ${evaluation.reason}');
  }
}

/// Та же сессия: новая не построена, прежняя не освобождена.
void _expectSameSession(
  _EditorSessions sessions,
  IntentionEditorViewModelProvider session,
) {
  expect(sessions.added, [same(session)]);
  expect(sessions.disposed, isEmpty);
}

/// Сессии формы создания, построенные и освобождённые за время теста.
final class _EditorSessions extends ProviderObserver {
  final added = <IntentionEditorViewModelProvider>[];
  final disposed = <IntentionEditorViewModelProvider>[];

  IntentionEditorViewModelProvider get single => added.single;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    if (context.provider case final IntentionEditorViewModelProvider provider) {
      added.add(provider);
    }
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    if (context.provider case final IntentionEditorViewModelProvider provider) {
      disposed.add(provider);
    }
  }

  IntentionEditorState state(WidgetTester tester) =>
      _container(tester).read(added.last);

  IntentionEditorViewModel notifier(WidgetTester tester) =>
      _container(tester).read(added.last.notifier);

  ProviderContainer _container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

ControlledCatalogRepository _repositoryWithTags() =>
    ControlledCatalogRepository()
      ..tagCatalogItems = _tags
      ..tagObservations = (id) => Stream.multi(
        (controller) => controller.add(
          TagReadSuccess(
            GraphSnapshot(
              value: _tags.where((tag) => tag.id == id).firstOrNull,
              revision: const TestCatalogRevision(0),
            ),
          ),
        ),
      );

/// Открывает каталог намерений с пустой выдачей в приложении с общей
/// поверхностью сообщений.
Future<AppRouter> _openCatalog(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  _EditorSessions sessions,
  Locale locale,
) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      observers: [sessions],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(
    0,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(IntentionCatalogPage), findsOneWidget);
  return router;
}

/// Отвечает на обновление каталога после подтверждённого создания.
void _completeCatalogRefresh(ControlledCatalogRepository repository) {
  if (repository.queries.length > 1) {
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
  }
}

Result<IntentionCommandSuccess> _savedResult() {
  final intention = testIntention(title: _userTitle);
  return ResultSuccess(
    IntentionSaved(
      intention,
      catalogMutation: IntentionCatalogCreated(
        revision: const TestCatalogRevision(1),
        entry: TestCatalogEntrySnapshot(
          testSummary(
            title: _userTitle,
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
          ),
        ),
      ),
    ),
  );
}

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));

TagId _tagId(int number) => switch (TagId.decode(
  '018f47c2-6b7d-7abc-8def-${number.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};
