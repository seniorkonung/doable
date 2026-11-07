import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/domain/intention_text.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_result.dart';
import '../../domain/action_path.dart';
import '../../domain/action_priority.dart';
import '../../domain/action_schedule.dart';

/// Открытие листа нового действия: одна сессия черновика со своим ключом
/// формы.
///
/// Каждое открытие создаёт новый запуск, поэтому второй лист поверх страницы,
/// открытой из первого, — самостоятельный черновик. Запуск различается
/// идентичностью и служит ключом сессии.
final class ActionEditorLaunch {
  // Не const: запуски различаются идентичностью даже при одинаковых данных.
  ActionEditorLaunch({required this.date, this.path});

  /// Дата нового действия, которую задал вход в создание.
  final CalendarDate date;

  /// Путь, с которого начинается черновик; без него путь пуст.
  final ActionDraftPath? path;

  /// Ключ формы сессии: координатор не принимает её повторную отправку во
  /// время записи, а по завершении записи ключ снова свободен.
  final formKey = ActionCreationFormKey();
}

/// Намерение пути черновика и название, под которым его показывает лист.
final class ActionDraftIntention {
  const ActionDraftIntention({required this.id, required this.title});

  final IntentionId id;
  final String title;
}

/// Звено пути черновика: вид связи от предыдущего намерения и само намерение.
final class ActionDraftPathStep {
  const ActionDraftPathStep({required this.relation, required this.intention});

  final LongTermRelationType relation;
  final ActionDraftIntention intention;
}

/// Непустой путь черновика от корневого намерения до конечного.
///
/// Форму пути проверяет [ActionPath]; что намерения активны, а связи
/// существуют, проверяет команда создания.
final class ActionDraftPath {
  factory ActionDraftPath({
    required ActionDraftIntention root,
    Iterable<ActionDraftPathStep> steps = const [],
  }) {
    final ordered = List<ActionDraftPathStep>.unmodifiable(steps);
    return ActionDraftPath._(
      root,
      ordered,
      ActionPath([root.id, for (final step in ordered) step.intention.id]),
    );
  }

  const ActionDraftPath._(this.root, this.steps, this.path);

  final ActionDraftIntention root;
  final List<ActionDraftPathStep> steps;

  /// Путь команды создания.
  final ActionPath path;

  /// Намерения пути от корневого до конечного.
  List<ActionDraftIntention> get intentions => [
    root,
    for (final step in steps) step.intention,
  ];
}

/// Данные будущего действия. Тексты хранятся так, как введены: их проверяет
/// отправка.
final class ActionEditorDraft {
  const ActionEditorDraft({
    required this.title,
    required this.description,
    required this.path,
    required this.date,
    required this.schedule,
    required this.priority,
  });

  /// Новая сессия начинается со времени «Весь день» и приоритета P4
  /// независимо от пути и прежних сессий.
  ActionEditorDraft.initial(ActionEditorLaunch launch)
    : title = '',
      description = '',
      path = launch.path,
      date = launch.date,
      schedule = const ActionAllDay(),
      priority = ActionPriority.p4;

  final String title;
  final String description;
  final ActionDraftPath? path;
  final CalendarDate date;
  final ActionSchedule schedule;
  final ActionPriority priority;

  /// Введён ли текст, потерю которого закрытие должно подтвердить.
  bool get hasText => title.trim().isNotEmpty || description.trim().isNotEmpty;

  /// Название не пусто и путь выбран.
  bool get isComplete => !IntentionText.isBlankTitle(title) && path != null;

  ActionEditorDraft copyWith({
    String? title,
    String? description,
    ActionDraftPath? path,
    CalendarDate? date,
    ActionSchedule? schedule,
    ActionPriority? priority,
  }) => ActionEditorDraft(
    title: title ?? this.title,
    description: description ?? this.description,
    path: path ?? this.path,
    date: date ?? this.date,
    schedule: schedule ?? this.schedule,
    priority: priority ?? this.priority,
  );
}

/// Ход отправки черновика.
sealed class ActionEditorSubmission {
  const ActionEditorSubmission();
}

/// Черновик редактируется, отправки нет.
final class ActionEditorEditing extends ActionEditorSubmission {
  const ActionEditorEditing();
}

/// Введённый текст не прошёл проверку, и команда не отправлена. Причина
/// поля живёт до его правки.
final class ActionEditorInputRejected extends ActionEditorSubmission {
  const ActionEditorInputRejected({this.title, this.description})
    : assert(title != null || description != null);

  final IntentionTextValidationReason? title;
  final IntentionTextValidationReason? description;
}

/// Принятая команда создания выполняется: черновик зафиксирован.
final class ActionEditorCreating extends ActionEditorSubmission {
  const ActionEditorCreating();
}

/// Создание отклонено; поля и путь остались в черновике.
///
/// [presentation] — право сессии предъявить отказ в своём листе. Право,
/// которое состояние перестало публиковать неподтверждённым, сессия передаёт
/// общей поверхности.
final class ActionEditorFailed extends ActionEditorSubmission {
  const ActionEditorFailed(this.failure, {this.presentation});

  final ActionCommandFailure failure;
  final GraphInitiatorPresentationClaim? presentation;

  /// Неизменённый черновик отправляется повторно только после доказанно
  /// временной недоступности.
  bool get canRetry => failure is ActionUnavailableFailure;
}

/// Решение сессии о запросе закрытия листа.
enum ActionEditorCloseDecision {
  /// Лист закрывается без вопроса; сессия уже завершена.
  close,

  /// Введён текст: нужен ответ на «Отменить новое действие?».
  ask,
}

/// Состояние сессии листа нового действия. Сессия не имеет завершающего
/// успеха: после создания она снова принимает ввод с очищенными названием и
/// описанием и заканчивается только закрытием листа.
final class ActionEditorState {
  const ActionEditorState._({
    required this.draft,
    required this.submission,
    required this.isClosed,
  });

  ActionEditorState.initial(ActionEditorLaunch launch)
    : draft = ActionEditorDraft.initial(launch),
      submission = const ActionEditorEditing(),
      isClosed = false;

  final ActionEditorDraft draft;
  final ActionEditorSubmission submission;

  /// Лист закрыт по запросу: черновик больше не меняется.
  final bool isClosed;

  /// Принимает ли черновик правки.
  bool get isEditable => !isClosed && submission is! ActionEditorCreating;

  /// Право отказа, которое публикует состояние.
  GraphInitiatorPresentationClaim? get failurePresentation =>
      switch (submission) {
        ActionEditorFailed(:final presentation) when !isClosed => presentation,
        _ => null,
      };

  bool get canSubmit =>
      isEditable &&
      draft.isComplete &&
      switch (submission) {
        ActionEditorEditing() => true,
        final ActionEditorFailed failed => failed.canRetry,
        ActionEditorInputRejected() || ActionEditorCreating() => false,
      };

  /// Спросит ли закрытие о потере текста. Во время создания лист
  /// закрывается без вопроса: команда продолжится.
  bool get asksOnClose =>
      !isClosed && submission is! ActionEditorCreating && draft.hasText;

  ActionEditorState withTitle(String value) => _edited(
    draft.copyWith(title: value),
    submission: switch (submission) {
      ActionEditorInputRejected(:final description) =>
        description == null
            ? const ActionEditorEditing()
            : ActionEditorInputRejected(description: description),
      _ => _failureAfterValueEdit(),
    },
  );

  ActionEditorState withDescription(String value) => _edited(
    draft.copyWith(description: value),
    submission: switch (submission) {
      ActionEditorInputRejected(:final title) =>
        title == null
            ? const ActionEditorEditing()
            : ActionEditorInputRejected(title: title),
      _ => _failureAfterValueEdit(),
    },
  );

  ActionEditorState withDate(CalendarDate value) => _edited(
    draft.copyWith(date: value),
    submission: _failureAfterValueEdit(),
  );

  ActionEditorState withPath(ActionDraftPath value) => _edited(
    draft.copyWith(path: value),
    submission: switch (submission) {
      ActionEditorFailed() => const ActionEditorEditing(),
      _ => submission,
    },
  );

  ActionEditorState withSchedule(ActionSchedule value) => _edited(
    draft.copyWith(schedule: value),
    submission: _failureAfterValueEdit(),
  );

  ActionEditorState withPriority(ActionPriority value) => _edited(
    draft.copyWith(priority: value),
    submission: _failureAfterValueEdit(),
  );

  ActionEditorState withSubmission(ActionEditorSubmission value) =>
      ActionEditorState._(draft: draft, submission: value, isClosed: isClosed);

  /// Подтверждённое создание очищает название и описание, а путь, дату, время
  /// и приоритет оставляет для следующего действия.
  ActionEditorState created() => ActionEditorState._(
    draft: draft.copyWith(title: '', description: ''),
    submission: const ActionEditorEditing(),
    isClosed: isClosed,
  );

  ActionEditorState closed() =>
      ActionEditorState._(draft: draft, submission: submission, isClosed: true);

  ActionEditorState _edited(
    ActionEditorDraft draft, {
    required ActionEditorSubmission submission,
  }) => ActionEditorState._(
    draft: draft,
    submission: submission,
    isClosed: isClosed,
  );

  /// Правка значения снимает отказ создания, кроме конфликта пути: его снимает
  /// только смена пути. Проверка текста остаётся у своего поля.
  ActionEditorSubmission _failureAfterValueEdit() => switch (submission) {
    ActionEditorFailed(failure: ActionPathConflictFailure()) => submission,
    ActionEditorFailed() => const ActionEditorEditing(),
    ActionEditorEditing() ||
    ActionEditorInputRejected() ||
    ActionEditorCreating() => submission,
  };
}
