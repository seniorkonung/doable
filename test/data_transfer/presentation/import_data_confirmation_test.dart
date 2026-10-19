import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data_transfer/presentation/import_data_confirmation.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Момент сохранения файла: начало 3 октября 2026 года по местному времени,
/// когда в UTC для части часовых поясов ещё 2 октября.
final _savedAt = DateTime(2026, 10, 3, 0, 30);

void main() {
  for (final (language, title, facts, replaces, cancel, confirm) in [
    (
      'ru',
      'Импортировать эту копию?',
      'Она сохранена 3 октября 2026 года и содержит 12 намерений, 14 связей, '
          '96 дневных выборов и 11 тегов.',
      'Она заменит всё, что сейчас есть в Doable. Сначала текущее состояние '
          'сохраняется как резервная копия.',
      'Отмена',
      'Импортировать и заменить',
    ),
    (
      'en',
      'Import this copy?',
      'It was saved on 3 October 2026 and holds 12 intentions, 14 relations, '
          '96 daily choices and 11 tags.',
      'It will replace everything now in Doable. A backup of the current '
          'state is made first.',
      'Cancel',
      'Import and replace',
    ),
  ]) {
    testWidgets('$language: подтверждение показывает дату сохранения и состав '
        'файла и предупреждает, что импорт заменит всё', (tester) async {
      await _openConfirmation(
        tester,
        language: language,
        header: _header(
          intentions: 12,
          longTermRelations: 14,
          dailyChoices: 96,
          tags: 11,
        ),
      );

      expect(_dialogTexts(tester), [title, facts, replaces, cancel, confirm]);
    });
  }

  for (final (language, compositions) in [
    (
      'ru',
      {
        1: '1 намерение, 1 связь, 1 дневной выбор и 1 тег',
        2: '2 намерения, 2 связи, 2 дневных выбора и 2 тега',
        5: '5 намерений, 5 связей, 5 дневных выборов и 5 тегов',
        21: '21 намерение, 21 связь, 21 дневной выбор и 21 тег',
      },
    ),
    (
      'en',
      {
        1: '1 intention, 1 relation, 1 daily choice and 1 tag',
        2: '2 intentions, 2 relations, 2 daily choices and 2 tags',
        5: '5 intentions, 5 relations, 5 daily choices and 5 tags',
        21: '21 intentions, 21 relations, 21 daily choices and 21 tags',
      },
    ),
  ]) {
    testWidgets('$language: количества файла согласуются с числом', (
      tester,
    ) async {
      for (final MapEntry(key: count, value: composition)
          in compositions.entries) {
        await _openConfirmation(
          tester,
          language: language,
          header: _header(
            intentions: count,
            longTermRelations: count,
            dailyChoices: count,
            tags: count,
          ),
        );

        expect(find.textContaining(composition), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('«Импортировать и заменить» подтверждает импорт', (tester) async {
    final confirmation = await _openConfirmation(tester);

    await tester.tap(find.text('Импортировать и заменить'));
    await tester.pumpAndSettle();

    expect(await confirmation, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('«Отмена» отказывается от импорта', (tester) async {
    final confirmation = await _openConfirmation(tester);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(await confirmation, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('системное «назад» закрывает подтверждение отказом от импорта', (
    tester,
  ) async {
    final confirmation = await _openConfirmation(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(await confirmation, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('экранный диктор называет подтверждение и читает его текст и '
      'действия', (tester) async {
    final semantics = tester.ensureSemantics();
    const facts =
        'Она сохранена 3 октября 2026 года и содержит 12 намерений, '
        '14 связей, 96 дневных выборов и 11 тегов.';
    const replaces =
        'Она заменит всё, что сейчас есть в Doable. Сначала текущее '
        'состояние сохраняется как резервная копия.';
    await _openConfirmation(
      tester,
      header: _header(
        intentions: 12,
        longTermRelations: 14,
        dailyChoices: 96,
        tags: 11,
      ),
    );

    final routeName = find.semantics.byFlag(SemanticsFlag.namesRoute);
    expect(routeName, findsOne);
    expect(
      routeName.evaluate().single,
      isSemantics(
        label: 'Импортировать эту копию?',
        scopesRoute: true,
        namesRoute: true,
      ),
    );
    for (final text in [facts, replaces]) {
      expect(tester.getSemantics(find.text(text)), isSemantics(label: text));
    }
    for (final action in ['Отмена', 'Импортировать и заменить']) {
      expect(
        tester.getSemantics(find.text(action)),
        isSemantics(
          label: action,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });
}

/// Заголовок файла, сохранённого в момент [_savedAt]. Назначения тегов
/// подтверждение не называет.
GraphFormatHeader _header({
  int intentions = 3,
  int longTermRelations = 2,
  int dailyChoices = 4,
  int tags = 1,
}) => GraphFormatHeader(
  writtenAt: _savedAt,
  counts: GraphRecordCounts(
    tags: tags,
    intentions: intentions,
    tagAssignments: 7,
    longTermRelations: longTermRelations,
    dailyChoices: dailyChoices,
  ),
);

/// Тексты открытого подтверждения сверху вниз.
List<String?> _dialogTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

/// Открывает над страницей подтверждение импорта файла с заголовком
/// [header] и возвращает его исход.
Future<Future<bool>> _openConfirmation(
  WidgetTester tester, {
  GraphFormatHeader? header,
  String language = 'ru',
}) async {
  late Future<bool> confirmation;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: doableTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => confirmation = confirmGraphImport(
                context,
                header: header ?? _header(),
              ),
              child: const Text('Открыть подтверждение'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть подтверждение'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  return confirmation;
}
