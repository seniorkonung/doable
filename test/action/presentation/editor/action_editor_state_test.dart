import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/presentation/editor/action_editor_state.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_editor_controls.dart';
import '../../../support/action_panel_fixture.dart';

void main() {
  test('конфликт снимается только подтверждённым целым путём', () {
    final whole = actionDetailsFixture().path;
    final broken = ActionSavedPath(
      root: whole.root,
      steps: [
        ActionPathStep(
          link: const DeletedActionPathLink(LongTermRelationType.need),
          intention: whole.steps.single.intention,
        ),
      ],
    );
    final draftPath = ActionDraftPath(
      root: ActionDraftIntention(id: whole.root.id, title: whole.root.title),
      steps: [
        ActionDraftPathStep(
          relation: whole.steps.single.link.type,
          intention: ActionDraftIntention(
            id: whole.steps.single.intention.id,
            title: whole.steps.single.intention.title,
          ),
        ),
      ],
    );
    final failed =
        ActionEditorState.initial(
              ActionEditorLaunch(date: actionEditorToday, path: draftPath),
            )
            .withTitle('Прогулка')
            .withDescription('В парке')
            .withSubmission(
              const ActionEditorFailed(ActionPathConflictFailure()),
            );

    for (final path in [broken, null]) {
      final state = failed.withPathState(path);
      expect(state.submission, isA<ActionEditorFailed>());
      expect(state.canSubmit, isFalse);
    }
    expect(failed.withTitle('Другое название').canSubmit, isFalse);
    expect(failed.withDescription('Другое описание').canSubmit, isFalse);
    expect(failed.withPath(draftPath).canSubmit, isTrue);
    final recovered = failed.withPathState(whole);
    expect(recovered.submission, isA<ActionEditorEditing>());
    expect(recovered.canSubmit, isTrue);
    expect(recovered.draft, same(failed.draft));

    for (final submission in [
      const ActionEditorFailed(ActionCorruptionFailure()),
      const ActionEditorEditing(),
      const ActionEditorInputRejected(
        title: IntentionTextValidationReason.tooLong,
      ),
      const ActionEditorCreating(),
    ]) {
      final state = failed.withSubmission(submission);
      expect(state.withPathState(whole).submission, same(submission));
    }
  });
}
