import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import 'relation_form_test_support.dart';

/// Оба предвыбранных входа используют тот же поиск, что и пустая роль.
void defineRelationParticipantSelectionTests({
  required Future<AppRouter> Function(
    WidgetTester,
    ControlledRelationFormRepository,
    RelationDirection,
  )
  openForm,
}) {
  for (final (name, direction, firstRole, secondRole) in [
    ('Исходящий', RelationDirection.outgoing, 'source', 'related'),
    ('Входящий', RelationDirection.incoming, 'related', 'source'),
  ]) {
    testWidgets(
      '$name вход: повторный выбор, исключение другой роли и отмена',
      (tester) async {
        final repository = ControlledRelationFormRepository();
        addTearDown(repository.dispose);
        final router = await openForm(tester, repository, direction);
        const title = 'Текущее намерение';
        final current = testSummary(index: 1, title: title);
        final sameTitle = testSummary(index: 2, title: title);
        const description = 'Черновик связи';
        final descriptionField = find.byKey(
          const ValueKey('relation-editor-description'),
        );
        await tester.enterText(descriptionField, description);
        await tester.tap(
          find.byKey(const ValueKey('relation-editor-type-can')),
        );
        await tester.tap(
          find.byKey(const ValueKey('relation-editor-priority-p3')),
        );
        await tester.pumpAndSettle();

        // Пока другая роль пуста, текущее значение доступно для повторного выбора.
        await tester.tap(
          find.byKey(ValueKey('relation-editor-change-$firstRole')),
        );
        await _settlePicker(tester);
        expect(router.current.name, RelationParticipantPickerRoute.name);
        expect(repository.catalogQueries[1].excludedIntentionId, isNull);
        repository.completeCatalogPage(1, [current, sameTitle]);
        await tester.pumpAndSettle();
        expect(find.text(title), findsNWidgets(2));
        await tester.tap(find.text(title).first);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ValueKey('relation-editor-select-$secondRole')),
        );
        await _settlePicker(tester);
        expect(repository.catalogQueries[2].excludedIntentionId, current.id);
        repository.completeCatalogPage(2, [current, sameTitle]);
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();

        // Из заполненной пары исключается только другая роль, даже при том же имени.
        await tester.tap(
          find.byKey(ValueKey('relation-editor-change-$firstRole')),
        );
        await _settlePicker(tester);
        expect(repository.catalogQueries[3].excludedIntentionId, sameTitle.id);
        repository.completeCatalogPage(3, [current, sameTitle]);
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ValueKey('relation-editor-change-$secondRole')),
        );
        await _settlePicker(tester);
        await tester.tap(
          find.byKey(const ValueKey('participant-picker-cancel')),
        );
        await tester.pumpAndSettle();
        expect(router.current.name, RelationEditorRoute.name);
        expect(
          tester.widget<TextField>(descriptionField).controller!.text,
          description,
        );
        expect(repository.relationCommands, isEmpty);

        await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
        await tester.pump();
        expect(repository.relationCommands, hasLength(1));
        final command = repository.commandAt(0);
        expect(
          command.sourceIntentionId,
          direction == RelationDirection.outgoing ? current.id : sameTitle.id,
        );
        expect(
          command.relatedIntentionId,
          direction == RelationDirection.outgoing ? sameTitle.id : current.id,
        );
        expect(command.type, LongTermRelationType.can);
        expect(command.priority, RelationPriority.p3);
        expect(command.description?.value, description);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _settlePicker(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
