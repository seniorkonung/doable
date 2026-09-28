import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_delete_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'подтверждение удаления объясняет полный охват на ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final name = '${'Длинный тег ' * 18}Дом';
        final tag = Tag(
          id: (TagId.decode(
            '018f0b5d-6b2e-7c80-8000-000000000001',
          ) as TagIdDecodingSuccess).id,
          name: TagName.fromInput(name),
        );
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      result = await confirmTagDeletion(context, tag),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.textContaining(name), findsWidgets);
        expect(
          find.byKey(const ValueKey('tag-delete-confirm')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('tag-delete-cancel')), findsOneWidget);
        final message = find.byKey(const ValueKey('tag-delete-scope'));
        expect(message, findsOneWidget);
        final text = tester.widget<Text>(message).data!;
        for (final term
            in locale.languageCode == 'ru'
                ? [
                    'необратимо',
                    'активным',
                    'архивированным',
                    'намерениям',
                    'связям',
                    'незагруженные',
                    'сохраняются',
                    'дневные выборы',
                  ]
                : [
                    'permanently',
                    'active',
                    'archived',
                    'intentions',
                    'relations',
                    'not loaded',
                    'remain',
                    'daily choices',
                  ]) {
          expect(text.toLowerCase(), contains(term));
        }
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('tag-delete-cancel')),
        );
        await tester.tap(find.byKey(const ValueKey('tag-delete-cancel')));
        await tester.pumpAndSettle();
        expect(result, isFalse);
      },
    );
  }
}
