import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/inline_text.dart';

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

  testWidgets('показывает данные и переход', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
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

  testWidgets('показывает точку и кольцо перед названиями тегов в порядке '
      'сводки на двух языках', (tester) async {
    final tags = [_tag(1, 'Здоровье', color: TagColor.blue), _tag(2, 'Отдых')];
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

    final tagsLine = findTextIgnoringInlineWidgets('Теги: Здоровье, Отдых');
    expect(tagsLine, findsOneWidget);
    expect(
      tester.getTopLeft(tagsLine).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.text('Пройти пешком до парка')).dy,
      ),
    );
    _expectDotsBeforeNames(tester, tagsLine, tags);

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
    final reversedLine = findTextIgnoringInlineWidgets('Tags: Отдых, Здоровье');
    expect(reversedLine, findsOneWidget);
    _expectDotsBeforeNames(tester, reversedLine, tags.reversed.toList());
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
    expect(find.byType(TagDot), findsNothing);
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
    // Отсутствие данных в строке не зависит от языка интерфейса.
    for (final locale in const [Locale('ru')]) {
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
      expect(find.byType(TagDot), findsNothing);
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

    final line = findTextIgnoringInlineWidgets('Теги: ${longNames.join(', ')}');
    expect(line, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: line, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
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
          confirmedTags: [
            _tag(1, 'Здоровье', color: TagColor.blue),
            _tag(2, 'Отдых'),
          ],
          onTap: () => opened++,
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(
      node.label,
      'Быть здоровым\nТеги: Здоровье, Отдых\nГотово к действию\n'
      'В архиве\nАктивных связей: 2',
    );
    expect(node.childrenCount, 0);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    // Строка тегов не образует отдельного узла и собственной цели нажатия.
    final tagsLine = findTextIgnoringInlineWidgets('Теги: Здоровье, Отдых');
    expect(tester.getSemantics(tagsLine).id, node.id);
    expect(
      find.descendant(
        of: find.byType(IntentionSummaryView),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );

    await tester.tap(tagsLine);
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

  testWidgets('длинное название не скрывает название, теги '
      'и количество активных связей', (tester) async {
    const longTitle =
        'Научиться хорошо плавать и перестать бояться глубины в открытой '
        'воде даже при сильном волнении и холодной погоде';
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: longTitle,
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(5),
          confirmedTags: [_tag(1, 'Здоровье'), _tag(2, 'Отдых')],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final rowRect = tester.getRect(find.byType(IntentionSummaryView));
    final titleFinder = find.text(longTitle);
    final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
    expect(titleParagraph.didExceedMaxLines, isFalse);
    for (final text in const ['Теги: Здоровье, Отдых', 'Активных связей: 5']) {
      final line = findTextIgnoringInlineWidgets(text);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: line, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(rowRect.contains(tester.getRect(line).bottomRight), isTrue);
    }
  });
}

void _expectDotsBeforeNames(WidgetTester tester, Finder line, List<Tag> tags) {
  final dots = find.descendant(of: line, matching: find.byType(TagDot));
  expect(dots, findsNWidgets(tags.length));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: line, matching: find.byType(RichText)),
  );
  final text = paragraph.text.toPlainText();
  var previousNameRight = tester.getTopLeft(line).dx;
  for (final (index, tag) in tags.indexed) {
    final dot = dots.at(index);
    expect(tester.getSize(dot), const Size.square(7));
    expect(
      tester.widget<TagDot>(dot).color,
      tag.color == TagColor.blue ? DoableTagColor.blue : null,
    );
    final nameStart = text.indexOf(tag.name.value);
    final nameBox = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: nameStart,
            extentOffset: nameStart + tag.name.value.length,
          ),
        )
        .single
        .toRect()
        .shift(paragraph.localToGlobal(Offset.zero));
    final dotRect = tester.getRect(dot);
    expect(dotRect.left, greaterThanOrEqualTo(previousNameRight));
    expect(dotRect.right, lessThan(nameBox.left));
    previousNameRight = nameBox.right;
  }
}

Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: (TagId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
  color: color,
);

Widget _testApp({
  required IntentionSummaryView view,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(body: ListView(children: [view])),
  ),
);
