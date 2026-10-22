import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_positions.dart';

void main() {
  test(
    'создание проверяет название, отклоняет повтор и сохраняет ввод при отказе',
    () async {
      final h = _Harness(TagEditorCreating(TagCreationFormKey()));
      addTearDown(h.dispose);
      h.model.changeName('  Дом  ');
      final first = h.model.submit();
      final second = h.model.submit();
      expect(h.repository.commands, hasLength(1));
      final command = h.repository.commands.single.command as CreateTag;
      expect(command.name.value, 'Дом');
      expect(command.color, isNull);
      await second;
      h.repository.failCommand(0, const TagUnavailableFailure());
      await first;
      expect(h.state.input, '  Дом  ');
      expect(h.state.status, isA<TagEditorSubmissionFailed>());
      expect(h.state.canSubmit, isTrue);
    },
  );

  test('правка названия цветного тега отправляет его цвет и сохраняет цвет после отказа', () async {
    final h = _Harness(TagEditorRenaming(_tag(1, 'Дом', color: TagColor.blue)));
    addTearDown(h.dispose);
    expect(h.state.color, TagColor.blue);
    h.model.changeName('Работа');
    expect(h.state.color, TagColor.blue);
    final submit = h.model.submit();
    h.repository.failCommand(0, TagNameOccupiedFailure(_id(2)));
    await submit;
    expect(h.state.input, 'Работа');
    expect(h.state.color, TagColor.blue);

    h.model.changeName('Быт');
    final retry = h.model.submit();
    final commands = [
      for (final request in h.repository.commands) request.command as UpdateTag,
    ];
    expect(commands.map((command) => command.name.value), ['Работа', 'Быт']);
    expect(commands.map((command) => command.color), [
      TagColor.blue,
      TagColor.blue,
    ]);
    h.repository.failCommand(1, const TagUnavailableFailure());
    await retry;
  });

  test('неизвестный отказ сохраняет ввод без обычного повтора', () async {
    final h = _Harness(TagEditorCreating(TagCreationFormKey()));
    addTearDown(h.dispose);
    h.model.changeName('Дом');
    final submit = h.model.submit();
    h.repository.failCommand(0, const TagUnexpectedFailure());
    await submit;
    h.model.changeName('Другое');
    expect(h.state.input, 'Другое');
    expect(h.state.canSubmit, isFalse);
  });

  test('пустое после удаления пробелов название делает создание недоступным '
      'без причины и сохраняет ввод', () async {
    final h = _Harness(TagEditorCreating(TagCreationFormKey()));
    addTearDown(h.dispose);
    h.model.changeName('   ');
    expect(h.state.nameCheck, isA<TagEditorNameEmpty>());
    expect(h.state.canSubmit, isFalse);
    await h.model.submit();
    expect(h.repository.commands, isEmpty);
    expect(h.state.input, '   ');
  });

  test(
    'недопустимый Unicode получает причину при вводе без вызова координатора',
    () async {
      final h = _Harness(TagEditorCreating(TagCreationFormKey()));
      addTearDown(h.dispose);
      h.model.changeName('Имя\u0000');
      expect(
        (h.state.nameCheck as TagEditorNameInvalid).reason,
        TagNameFailureReason.invalidUnicodeRepertoire,
      );
      expect(h.state.canSubmit, isFalse);
      await h.model.submit();
      expect(h.repository.commands, isEmpty);
      expect(h.state.input, 'Имя\u0000');
    },
  );

  test('название, совпадающее с тегом снимка без учёта регистра и пробелов, '
      'занято, а исправленное снова доступно', () async {
    final h = _Harness(
      TagEditorCreating(
        TagCreationFormKey(),
        existingNames: [TagName.fromInput('Дом')],
      ),
    );
    addTearDown(h.dispose);
    h.model.changeName('  дом  ');
    expect(h.state.nameCheck, isA<TagEditorNameOccupied>());
    expect(h.state.canSubmit, isFalse);
    await h.model.submit();
    expect(h.repository.commands, isEmpty);

    h.model.changeName('Домик');
    expect(h.state.canSubmit, isTrue);
  });

  test('принятое создание с начальным названием передаётся вызывающему до '
      'завершения и завершается после закрытия сессии', () async {
    final accepted = <TagCommandAccepted>[];
    final h = _Harness(
      TagEditorCreating(
        TagCreationFormKey(),
        initialName: 'парк',
        onCreationAccepted: accepted.add,
      ),
    );
    addTearDown(h.dispose);
    expect(h.state.input, 'парк');
    unawaited(h.model.submit());
    expect(accepted, hasLength(1));
    expect(
      (h.repository.commands.single.command as CreateTag).name.value,
      'парк',
    );

    h.model.closeSession();
    h.repository.succeedCommand(
      0,
      TagCreated(
        TagCreatedChange(revision: const _Revision(2), after: _tag(1, 'парк')),
      ),
    );
    final completion = await accepted.single.future;
    expect(
      completion.result,
      isA<GraphResultSuccess<TagCommandSuccess, TagCommandFailure>>(),
    );
  });

  test(
    'подтверждённое создание завершает сессию тегом из результата команды',
    () async {
      final h = _Harness(TagEditorCreating(TagCreationFormKey()));
      addTearDown(h.dispose);
      h.model.changeName('Дом');
      final submit = h.model.submit();
      h.repository.succeedCommand(
        0,
        TagCreated(
          TagCreatedChange(revision: const _Revision(2), after: _tag(1, 'Дом')),
        ),
      );
      await submit;
      final saved = (h.state.event as TagEditorSaved).tag;
      expect(saved.id, _id(1));
      expect(saved.name.value, 'Дом');
      expect(h.state.canSubmit, isFalse);
    },
  );
}

final class _Harness {
  _Harness(TagEditorContext context) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(
      tagEditorViewModelProvider(context),
      (_, _) {},
    );
    _context = context;
  }

  final repository = _Repository();
  late final ProviderContainer container;
  late ProviderSubscription<TagEditorState> subscription;
  late TagEditorContext _context;
  TagEditorViewModel get model =>
      container.read(tagEditorViewModelProvider(_context).notifier);
  TagEditorState get state =>
      container.read(tagEditorViewModelProvider(_context));

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _CommandRequest {
  _CommandRequest(this.command);
  final TagCommand command;
  final completer = Completer<TagCommandResult>();
}

final class _Repository extends Fake implements PersonalGraphRepository {
  final commands = <_CommandRequest>[];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final request = _CommandRequest(command as TagCommand);
    commands.add(request);
    return await request.completer.future
        as GraphCommandResult<TSuccess, TFailure>;
  }

  void failCommand(int index, TagCommandFailure failure) =>
      commands[index].completer.complete(TagCommandFailed(failure));

  void succeedCommand(int index, TagCommandSuccess success) =>
      commands[index].completer.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(revision: const _Revision(2), value: success),
        ),
      );
}

final class _Revision implements GraphRevision {
  const _Revision(this.number);
  final int number;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(number: final n) when number < n => GraphRevisionOrder.older,
    _Revision(number: final n) when number > n => GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;
Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);
