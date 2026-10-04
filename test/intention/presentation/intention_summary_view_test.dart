import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('показывает подтверждённое количество активных связей на двух '
      'языках, не изменяя название', (tester) async {
    await tester.pumpWidget(
      _testApp(
        view: IntentionSummaryView(
          title: 'Позвонить врачу',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(3),
        ),
      ),
    );

    expect(find.text('Позвонить врачу'), findsOneWidget);
    expect(find.text('Active relations: 3'), findsOneWidget);

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Позвонить врачу',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(3),
        ),
      ),
    );

    expect(find.text('Позвонить врачу'), findsOneWidget);
    expect(find.text('Активных связей: 3'), findsOneWidget);
  });

  testWidgets('показывает явный ноль активных связей', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Выбрать страховку',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(0),
        ),
      ),
    );

    expect(find.text('Активных связей: 0'), findsOneWidget);
  });

  testWidgets('сохраняет прежнее число при ошибке обновления', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Много ходить',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: OutdatedActiveRelationCount(4),
        ),
      ),
    );

    expect(find.text('Активных связей: 4'), findsOneWidget);
    expect(
      find.text('Не удалось обновить количество активных связей.'),
      findsOneWidget,
    );
  });

  testWidgets('не изображает неизвестное количество нулём', (tester) async {
    await tester.pumpWidget(
      _testApp(
        view: const IntentionSummaryView(
          title: 'Иметь хорошую обувь',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: LoadingActiveRelationCount(),
        ),
      ),
    );

    expect(find.text('Loading the active relation count…'), findsOneWidget);
    expect(find.text('Active relations: 0'), findsNothing);

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: const IntentionSummaryView(
          title: 'Иметь хорошую обувь',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: UnknownActiveRelationCount(),
        ),
      ),
    );

    expect(find.text('Количество активных связей неизвестно.'), findsOneWidget);
    expect(find.text('Активных связей: 0'), findsNothing);
  });

  testWidgets('представление участника сохраняет идентичность и явно '
      'показывает архив', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Сходить в магазин',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          activeRelationCount: ConfirmedActiveRelationCount(0),
        ),
      ),
    );

    expect(find.text('Сходить в магазин'), findsOneWidget);
    expect(find.text('В архиве'), findsOneWidget);
    expect(find.text('Активных связей: 0'), findsOneWidget);
  });

  testWidgets('семантика сообщает название, состояние и активное количество', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          traits: const ['Готово к действию'],
          activeRelationCount: ConfirmedActiveRelationCount(2),
          onTap: () {},
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(node.label, contains('Быть здоровым'));
    expect(node.label, contains('Готово к действию'));
    expect(node.label, contains('В архиве'));
    expect(node.label, contains('Активных связей: 2'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
  });

  testWidgets('увеличенный текст не скрывает данные и переход', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        textScaler: const TextScaler.linear(3),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          traits: const ['Готово к действию'],
          activeRelationCount: OutdatedActiveRelationCount(7),
          onTap: () => opened++,
        ),
      ),
    );

    expect(find.text('Быть здоровым'), findsOneWidget);
    expect(find.text('Готово к действию'), findsOneWidget);
    expect(find.text('В архиве'), findsOneWidget);
    expect(find.text('Активных связей: 7'), findsOneWidget);
    expect(
      find.text('Не удалось обновить количество активных связей.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Быть здоровым'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('показывает подтверждённые теги строкой названий в порядке '
      'сводки на двух языках', (tester) async {
    final tags = [_tag(1, 'Здоровье'), _tag(2, 'Отдых')];
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Пройти пешком до парка',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(1),
          confirmedTags: tags,
        ),
      ),
    );

    expect(find.text('Теги: Здоровье, Отдых'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Теги: Здоровье, Отдых')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.text('Пройти пешком до парка')).dy,
      ),
    );

    await tester.pumpWidget(
      _testApp(
        view: IntentionSummaryView(
          title: 'Пройти пешком до парка',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(1),
          confirmedTags: tags.reversed.toList(),
        ),
      ),
    );

    // Названия тегов не переводятся и идут в переданном порядке.
    expect(find.text('Tags: Отдых, Здоровье'), findsOneWidget);
  });

  testWidgets('показывает подтверждённый пустой состав тегов явной подписью '
      'на двух языках', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Выбрать страховку',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(0),
          confirmedTags: const [],
        ),
      ),
    );

    expect(find.text('Без тегов'), findsOneWidget);
    expect(find.textContaining('Теги:'), findsNothing);

    await tester.pumpWidget(
      _testApp(
        view: IntentionSummaryView(
          title: 'Выбрать страховку',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(0),
          confirmedTags: const [],
        ),
      ),
    );

    expect(find.text('No tags'), findsOneWidget);
    expect(find.textContaining('Tags:'), findsNothing);
  });

  testWidgets('не выводит строку тегов без их передачи', (tester) async {
    for (final locale in const [Locale('ru'), Locale('en')]) {
      await tester.pumpWidget(
        _testApp(
          locale: locale,
          view: IntentionSummaryView(
            title: 'Много ходить',
            archiveState: IntentionArchiveState.active,
            showArchiveState: false,
            activeRelationCount: ConfirmedActiveRelationCount(2),
          ),
        ),
      );

      expect(find.textContaining('Теги:'), findsNothing);
      expect(find.text('Без тегов'), findsNothing);
      expect(find.textContaining('Tags:'), findsNothing);
      expect(find.text('No tags'), findsNothing);
    }
  });

  testWidgets('длинные названия тегов переносятся без обрезки и '
      'преобразования', (tester) async {
    final longNames = [
      for (var index = 1; index <= 6; index++)
        'Очень длинное название тега номер $index с ПРОПИСНЫМИ и строчными',
    ];
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        textScaler: const TextScaler.linear(2),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(0),
          confirmedTags: [
            for (final (index, name) in longNames.indexed)
              _tag(index + 1, name),
          ],
        ),
      ),
    );

    final line = find.text('Теги: ${longNames.join(', ')}');
    expect(line, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(line);
    expect(paragraph.maxLines, isNull);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.softWrap, isTrue);
    expect(
      paragraph.size.height,
      greaterThan(2 * tester.getSize(find.text('Активных связей: 0')).height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('строка тегов входит в объединённую семантику результата без '
      'новых целей нажатия', (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          traits: const ['Готово к действию'],
          activeRelationCount: ConfirmedActiveRelationCount(2),
          confirmedTags: [_tag(1, 'Здоровье'), _tag(2, 'Отдых')],
          onTap: () => opened++,
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(node.label, contains('Быть здоровым'));
    expect(node.label, contains('Теги: Здоровье, Отдых'));
    expect(node.label, contains('Готово к действию'));
    expect(node.label, contains('В архиве'));
    expect(node.label, contains('Активных связей: 2'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    // Строка тегов не образует отдельного узла и собственной цели нажатия.
    expect(tester.getSemantics(find.text('Теги: Здоровье, Отдых')).id, node.id);
    expect(
      find.descendant(
        of: find.byType(IntentionSummaryView),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Теги: Здоровье, Отдых'));
    await tester.pump();
    expect(opened, 1);

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(2),
          confirmedTags: const [],
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(IntentionSummaryView)).label,
      contains('Без тегов'),
    );

    semantics.dispose();
  });

  testWidgets('избранное намерение показывает звезду, неизбранное — нет', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Гулять',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(1),
          confirmedFavoriteMark: FavoriteMark.favorite,
        ),
      ),
    );

    // Отметка различима формой: звезда есть только у избранного намерения.
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('Гулять'), findsOneWidget);

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Гулять',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(1),
          confirmedFavoriteMark: FavoriteMark.notFavorite,
        ),
      ),
    );

    expect(find.byType(Icon), findsNothing);
    expect(find.text('Гулять'), findsOneWidget);
  });

  testWidgets('не выводит отметку избранного без её передачи', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final locale in const [Locale('ru'), Locale('en')]) {
      await tester.pumpWidget(
        _testApp(
          locale: locale,
          view: IntentionSummaryView(
            title: 'Много ходить',
            archiveState: IntentionArchiveState.active,
            showArchiveState: false,
            activeRelationCount: ConfirmedActiveRelationCount(2),
          ),
        ),
      );

      expect(find.byType(Icon), findsNothing);
      final label = tester
          .getSemantics(find.byType(IntentionSummaryView))
          .label;
      expect(label, isNot(contains('Избранное намерение')));
      expect(label, isNot(contains('Favorite intention')));
    }
    semantics.dispose();
  });

  testWidgets('звезда входит в объединённую семантику строки с названием '
      'отметки на двух языках без новой цели нажатия', (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    IntentionSummaryView view(FavoriteMark mark) => IntentionSummaryView(
      title: 'Быть здоровым',
      archiveState: IntentionArchiveState.archived,
      showArchiveState: true,
      traits: const ['Готово к действию'],
      activeRelationCount: ConfirmedActiveRelationCount(2),
      confirmedTags: [_tag(1, 'Здоровье')],
      confirmedFavoriteMark: mark,
      onTap: () => opened++,
    );

    await tester.pumpWidget(
      _testApp(locale: const Locale('ru'), view: view(FavoriteMark.favorite)),
    );

    final node = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(node.label, contains('Быть здоровым'));
    expect(node.label, contains('Избранное намерение'));
    expect(node.label, contains('Теги: Здоровье'));
    expect(node.label, contains('Готово к действию'));
    expect(node.label, contains('В архиве'));
    expect(node.label, contains('Активных связей: 2'));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    // Звезда не образует отдельного узла, цели нажатия или действия.
    expect(tester.getSemantics(find.byIcon(Icons.star)).id, node.id);
    expect(data.customSemanticsActionIds ?? const <int>[], isEmpty);
    expect(
      find.descendant(
        of: find.byType(IntentionSummaryView),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(IntentionSummaryView),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.star));
    await tester.pump();
    expect(opened, 1);

    await tester.pumpWidget(_testApp(view: view(FavoriteMark.favorite)));
    expect(
      tester.getSemantics(find.byType(IntentionSummaryView)).label,
      contains('Favorite intention'),
    );

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: view(FavoriteMark.notFavorite),
      ),
    );
    expect(
      tester.getSemantics(find.byType(IntentionSummaryView)).label,
      isNot(contains('Избранное намерение')),
    );

    semantics.dispose();
  });

  testWidgets('длинное название и увеличенный текст не обрезают звезду и не '
      'скрывают название, теги и количество активных связей', (tester) async {
    const longTitle =
        'Научиться хорошо плавать и перестать бояться глубины в открытой '
        'воде даже при сильном волнении и холодной погоде';
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        textScaler: const TextScaler.linear(3),
        view: IntentionSummaryView(
          title: longTitle,
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(5),
          confirmedTags: [_tag(1, 'Здоровье'), _tag(2, 'Отдых')],
          confirmedFavoriteMark: FavoriteMark.favorite,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final rowRect = tester.getRect(find.byType(IntentionSummaryView));
    final starRect = tester.getRect(find.byIcon(Icons.star));
    // Звезда целиком внутри строки и не сжата до нуля.
    expect(starRect.width, greaterThan(0));
    expect(starRect.height, greaterThan(0));
    expect(rowRect.contains(starRect.topLeft), isTrue);
    expect(rowRect.contains(starRect.bottomRight), isTrue);
    // Звезда растёт вместе с текстом.
    expect(starRect.width, greaterThan(24));

    final titleFinder = find.text(longTitle);
    final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
    expect(titleParagraph.didExceedMaxLines, isFalse);
    // Название не заходит под звезду.
    expect(tester.getRect(titleFinder).overlaps(starRect), isFalse);
    for (final text in const ['Теги: Здоровье, Отдых', 'Активных связей: 5']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getRect(find.text(text)).overlaps(starRect), isFalse);
      expect(
        rowRect.contains(tester.getRect(find.text(text)).bottomRight),
        isTrue,
      );
    }
  });
}

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

Widget _testApp({
  required IntentionSummaryView view,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: Scaffold(body: ListView(children: [view])),
    ),
  ),
);
