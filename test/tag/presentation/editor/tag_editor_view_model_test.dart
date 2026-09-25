import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(
        (h.repository.commands.single.command as CreateTag).name.value,
        'Дом',
      );
      await second;
      h.repository.failCommand(0, const TagUnavailableFailure());
      await first;
      expect(h.state.input, '  Дом  ');
      expect(h.state.status, isA<TagEditorSubmissionFailed>());
      expect(h.state.failurePresentation, isNotNull);
      expect(h.state.canSubmit, isTrue);
    },
  );

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

  test(
    'недопустимый Unicode остаётся в форме без вызова координатора',
    () async {
      final h = _Harness(TagEditorCreating(TagCreationFormKey()));
      addTearDown(h.dispose);
      h.model.changeName('Имя\u0000');
      await h.model.submit();
      expect(h.repository.commands, isEmpty);
      expect(h.state.input, 'Имя\u0000');
      expect(
        (h.state.status as TagEditorSubmissionFailed).failure,
        isA<TagNameInputFailure>().having(
          (failure) => failure.reason,
          'причина',
          TagNameFailureReason.invalidUnicodeRepertoire,
        ),
      );
    },
  );

  test(
    'конфликт читает именно переданный id и не подменяет исчезнувший тег',
    () async {
      final h = _Harness(TagEditorCreating(TagCreationFormKey()));
      addTearDown(h.dispose);
      h.model.changeName('Дом');
      final submit = h.model.submit();
      h.repository.failCommand(0, TagNameOccupiedFailure(_id(1)));
      await submit;
      final selection = h.model.useExisting();
      expect(h.repository.readIds, [_id(1)]);
      h.repository.completeRead(0, null);
      await selection;
      expect(h.state.status, isA<TagEditorExistingMissing>());
      expect(h.state.event, isNull);
      expect(h.state.input, 'Дом');
      expect(h.repository.commands, hasLength(1));
    },
  );

  test(
    'выбор занятого тега возвращает прочитанный тег без новой команды',
    () async {
      final h = _Harness(TagEditorCreating(TagCreationFormKey()));
      addTearDown(h.dispose);
      h.model.changeName('Дом');
      final submit = h.model.submit();
      h.repository.failCommand(0, TagNameOccupiedFailure(_id(1)));
      await submit;
      final selection = h.model.useExisting();
      h.repository.completeRead(0, _tag(1, 'Быт'));
      await selection;
      expect(
        (h.state.event as TagEditorExistingSelected).tag.name.value,
        'Быт',
      );
      expect(h.repository.commands, hasLength(1));
      h.model.consumeEvent();
      expect(h.state.event, isNull);
    },
  );

  test(
    'уход сохраняет принятую команду и возврат не обходит блокировку тега',
    () async {
      final h = _Harness(TagEditorRenaming(_tag(1, 'Дом')));
      addTearDown(h.dispose);
      h.model.changeName('Быт');
      final first = h.model.submit();
      expect(h.repository.commands.single.command, isA<RenameTag>());
      h.model.closeSession();
      final returned = h.reopen(TagEditorRenaming(_tag(1, 'Дом')));
      returned.changeName('Семья');
      await returned.submit();
      expect(h.state.status, isA<TagEditorAlreadyRunning>());
      expect(h.state.input, 'Семья');
      expect(h.state.canSubmit, isFalse);
      expect(h.repository.commands, hasLength(1));
      h.repository.succeedCommand(
        0,
        TagRenamed(
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag(1, 'Дом'),
            after: _tag(1, 'Быт'),
          ),
        ),
      );
      await first;
      expect(h.state.status, isA<TagEditorIdle>());
      expect(h.state.input, 'Семья');
      expect(h.state.canSubmit, isTrue);
      expect(h.repository.commands, hasLength(1));
    },
  );

  test(
    'повторное открытие создания с прежним ключом не принимает вторую запись',
    () async {
      final formKey = TagCreationFormKey();
      final h = _Harness(TagEditorCreating(formKey));
      addTearDown(h.dispose);
      h.model.changeName('Дом');
      final first = h.model.submit();
      h.model.closeSession();
      final returned = h.reopen(TagEditorCreating(formKey));
      returned.changeName('Работа');
      await returned.submit();
      expect(h.state.status, isA<TagEditorAlreadyRunning>());
      expect(h.state.input, 'Работа');
      expect(h.state.canSubmit, isFalse);
      expect(h.repository.commands, hasLength(1));
      h.repository.failCommand(0, const TagUnavailableFailure());
      await first;
      expect(h.state.status, isA<TagEditorIdle>());
      expect(h.state.input, 'Работа');
      expect(h.state.canSubmit, isTrue);
    },
  );

  test('ошибка чтения после commit повторяет только чтение', () async {
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
    await pumpEventQueue();
    expect(h.repository.readIds, [_id(1)]);
    h.repository.failRead(0, const TagReadUnavailableFailure());
    await submit;
    expect(h.state.status, isA<TagEditorCommittedReadFailed>());
    expect(h.state.canSubmit, isFalse);
    final retry = h.model.retryCommittedRead();
    expect(h.repository.commands, hasLength(1));
    expect(h.repository.readIds, [_id(1), _id(1)]);
    h.repository.completeRead(1, _tag(1, 'Дом'));
    await retry;
    expect((h.state.event as TagEditorSaved).tag.id, _id(1));
  });

  test('повтор чтения после commit не принимает старую ревизию', () async {
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
    await pumpEventQueue();
    h.repository.failRead(0, const TagReadUnavailableFailure());
    await submit;
    final retry = h.model.retryCommittedRead();
    h.repository.completeRead(1, _tag(1, 'Старое'), revision: 1);
    await retry;
    expect(h.state.status, isA<TagEditorCommittedReadFailed>());
    expect(h.state.event, isNull);
    expect(h.repository.commands, hasLength(1));
  });
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

  TagEditorViewModel reopen(TagEditorContext context) {
    subscription.close();
    _context = context;
    subscription = container.listen(
      tagEditorViewModelProvider(context),
      (_, _) {},
    );
    return model;
  }

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
  final readIds = <TagId>[];
  final reads = <StreamController<TagReadResult>>[];

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

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    readIds.add(id);
    final controller = StreamController<TagReadResult>();
    reads.add(controller);
    return controller.stream;
  }

  void failCommand(int index, TagCommandFailure failure) =>
      commands[index].completer.complete(TagCommandFailed(failure));

  void succeedCommand(int index, TagCommandSuccess success) =>
      commands[index].completer.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(revision: const _Revision(2), value: success),
        ),
      );

  void completeRead(int index, Tag? tag, {int revision = 2}) =>
      reads[index].add(
        TagReadSuccess(
          GraphSnapshot(value: tag, revision: _Revision(revision)),
        ),
      );

  void failRead(int index, TagReadFailure failure) =>
      reads[index].add(TagReadError(failure));
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
Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
