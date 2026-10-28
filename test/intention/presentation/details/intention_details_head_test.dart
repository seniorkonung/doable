import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import 'details_test_support.dart';

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    final russian = locale.languageCode == 'ru';
    testWidgets('загрузка и отказ чтения сохраняют имя маршрута без видимого '
        'и пустого семантического заголовка: ${locale.languageCode}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      for (final result in <Result<Intention?>>[
        const ResultSuccess(null),
        const ResultFailure(IntentionUnavailableFailure()),
      ]) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention();
        await _pumpPage(tester, repository, intention, locale: locale);
        await waitForDetailRequests(repository, 1);

        void expectUnnamedBar() {
          expect(_barText, findsNothing);
          final routeName = russian
              ? 'Подробности намерения'
              : 'Intention details';
          expect(
            tester.getSemantics(find.bySemanticsLabel(routeName)),
            isSemantics(label: routeName, namesRoute: true, children: const []),
          );
          expect(find.semantics.byFlag(SemanticsFlag.isHeader), findsNothing);
          expect(
            find.bySemanticsLabel(russian ? 'Назад' : 'Back'),
            findsOneWidget,
          );
        }

        expectUnnamedBar();
        repository.detailRequests.single.add(result);
        await tester.pumpAndSettle();
        expectUnnamedBar();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      semantics.dispose();
    });

    testWidgets('после загрузки панель называет тип и показывает его значок: '
        '${locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final readiness in IntentionReadiness.values) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(readiness: readiness);
        await _pumpPage(tester, repository, intention, locale: locale);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests.single.add(ResultSuccess(intention));
        await tester.pumpAndSettle();

        final ready = readiness == IntentionReadiness.ready;
        final type = ready
            ? (russian ? 'Действие' : 'Action')
            : (russian ? 'Намерение' : 'Intention');
        final bar = tester.widget<TopBar>(find.byType(TopBar));
        expect(bar.title, type);
        expect(
          bar.titleIcon,
          ready ? DoableIconData.bolt : DoableIconData.intention,
        );
        expect(
          tester.getSemantics(_barText),
          isSemantics(
            label: type,
            namesRoute: true,
            isHeader: true,
            children: const [],
          ),
        );
        expect(
          find.bySemanticsLabel(
            russian ? 'Подробности намерения' : 'Intention details',
          ),
          findsNothing,
        );
        expect(
          tester.widget<PageHead>(find.byType(PageHead)).name,
          intention.title,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      semantics.dispose();
    });
  }

  for (final (locale, editLabel) in [
    (const Locale('ru'), 'Изменить название: Бегать'),
    (const Locale('en'), 'Edit the name: Бегать'),
  ]) {
    testWidgets('нажатие на название с доступным названием открывает экран '
        'изменения с этим названием: ${locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(title: 'Бегать');
      await _pumpPage(tester, repository, intention, locale: locale);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      final name = find.bySemanticsLabel(editLabel);
      expect(
        tester.getSemantics(name),
        isSemantics(
          label: editLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(name);
      await tester.pumpAndSettle();

      expect(find.byType(IntentionEditPage), findsOneWidget);
      expect(_editTitle(tester), 'Бегать');
      semantics.dispose();
    });
  }

  testWidgets('название недоступно и не открывает экран изменения, пока '
      'выполняется команда страницы', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _pumpPage(tester, repository, intention);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    final archive = find.byKey(const ValueKey('intention-details-archive'));
    await tester.ensureVisible(archive);
    await tester.pump();
    await tester.tap(archive);
    await tester.pump();
    final position = tester.state<ScrollableState>(_scrollable).position;
    position.jumpTo(0);
    await tester.pump();

    final name = find.bySemanticsLabel('Изменить название: Бегать');
    expect(
      tester.getSemantics(name),
      isSemantics(
        label: 'Изменить название: Бегать',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await tester.tap(find.text('Бегать'));
    // Индикатор выполняющейся команды не даёт кадрам успокоиться.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IntentionEditPage), findsNothing);
    semantics.dispose();
  });

  testWidgets('нажатие на название не открывает экран изменения, если '
      'команду приняла не страница и она ещё не отразила занятость', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _pumpPage(tester, repository, intention);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    final coordinator = ProviderScope.containerOf(
      tester.element(find.byType(IntentionDetailsPage)),
    ).read(graphCommandCoordinatorProvider.notifier);
    final busy = coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: intention.title,
    ) as IntentionCommandAccepted;
    coordinator.releaseInitiatorPresentation(busy.token);
    await tester.pump();
    expect(tester.widget<PageHead>(find.byType(PageHead)).onEdit, isNotNull);

    await tester.tap(find.text('Бегать'));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditPage), findsNothing);
  });

  testWidgets('скрытая шапка переносит полное название в панель без значка, '
      'приглушает архивное и возвращает тип при прокрутке назад', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      title: 'Поддерживать здоровье и хорошее самочувствие каждый день ' * 3,
      archiveState: IntentionArchiveState.archived,
    );
    await _pumpPage(tester, repository, intention);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    final head = find.byType(PageHead);
    final headExtent = tester.getSize(head).height;
    final position = tester.state<ScrollableState>(_scrollable).position;
    position.jumpTo(headExtent - 1);
    await tester.pump();
    expect(tester.widget<Text>(_barText).data, 'Намерение');
    position.jumpTo(headExtent);
    await tester.pump();
    final bar = tester.widget<TopBar>(find.byType(TopBar));
    expect(bar.title, intention.title);
    expect(bar.titleIcon, isNull);
    expect(bar.muted, isTrue);
    final paragraph = tester.renderObject<RenderParagraph>(_barText);
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(paragraph.overflow, TextOverflow.ellipsis);

    position.jumpTo(0);
    await tester.pump();
    expect(tester.widget<Text>(_barText).data, 'Намерение');
    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsNothing);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  testWidgets('изменение масштаба текста пересчитывает порог скрытия шапки', (
    tester,
  ) async {
    final scale = ValueNotifier<TextScaler>(TextScaler.noScaling);
    addTearDown(scale.dispose);
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      title: 'Поддерживать здоровье и хорошее самочувствие каждый день ' * 3,
    );
    await _pumpPage(tester, repository, intention, scale: scale);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();
    final oldExtent = tester.getSize(find.byType(PageHead)).height;
    final position = tester.state<ScrollableState>(_scrollable).position;
    position.jumpTo(oldExtent + 1);
    await tester.pump();
    expect(tester.widget<Text>(_barText).data, intention.title);

    scale.value = const TextScaler.linear(2);
    await tester.pumpAndSettle();
    final newExtent = tester.getSize(find.byType(PageHead)).height;
    expect(newExtent, greaterThan(oldExtent));
    expect(tester.widget<Text>(_barText).data, 'Намерение');
    position.jumpTo(newExtent);
    await tester.pump();
    expect(tester.widget<Text>(_barText).data, intention.title);
    expect(tester.widget<TopBar>(find.byType(TopBar)).muted, isFalse);
    expect(tester.takeException(), isNull);
  });
}

final _barText = find.descendant(
  of: find.byType(TopBar),
  matching: find.byType(Text),
);
String _editTitle(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('intention-edit-title')),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

final _scrollable = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _pumpPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  Intention intention, {
  Locale locale = const Locale('ru'),
  ValueNotifier<TextScaler>? scale,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: OrdinaryPageTestApp(
        locale: locale,
        routes: [AutoRoute(page: IntentionEditRoute.page)],
        builder: scale == null
            ? null
            : (context, child) => ValueListenableBuilder(
                valueListenable: scale,
                builder: (context, value, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: value),
                  child: child!,
                ),
              ),
        home: IntentionDetailsPage(intentionId: intention.id),
      ),
    ),
  );
  await tester.pump();
}
