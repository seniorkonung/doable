import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_day.dart';
import '../../application/action_list_item.dart';

/// Загруженная часть секции и её число действий на ревизии общей пары.
final class ActionDaySectionSnapshot {
  ActionDaySectionSnapshot._({
    required List<ActionListItem> items,
    required this.totalCount,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<ActionListItem> items;
  final int totalCount;
  final ActionDayCursor? nextCursor;
}

/// Конструктор закрыт: пару создаёт только сборка порций одной ревизии.
final class ActionDaySnapshot {
  const ActionDaySnapshot._({
    required this.incomplete,
    required this.completed,
    required this.hasTimedActions,
    required this.revision,
  });

  final ActionDaySectionSnapshot incomplete;
  final ActionDaySectionSnapshot completed;

  /// Учитывает действия обеих секций, включая ещё не полученные порции.
  final bool hasTimedActions;
  final GraphRevision revision;
}

sealed class ActionDayAssemblyResult {
  const ActionDayAssemblyResult();
}

final class ActionDayAssemblyReady extends ActionDayAssemblyResult {
  const ActionDayAssemblyReady(this.snapshot);

  final ActionDaySnapshot snapshot;
}

final class ActionDayAssemblyFailed extends ActionDayAssemblyResult {
  const ActionDayAssemblyFailed(this.failure);

  final ActionDayReadFailure failure;
}

final class ActionDayAssemblyCancelled extends ActionDayAssemblyResult {
  const ActionDayAssemblyCancelled();
}

/// Получает первые порции обеих секций, затем дочитывает каждую до её целевого
/// объёма или конца. Объём округляется вверх до целой порции; остаток не читается.
/// Все чтения используют отдельные транзакции репозитория.
///
/// [isCurrent] проверяет поколение запроса и жизнь экземпляра. Отмена не прерывает
/// уже начатое чтение, но отбрасывает его ответ и прекращает следующие чтения.
/// [acceptsRevision] проверяет ревизию относительно подтверждённых изменений,
/// известных модели; отклонение требует новой сборки, а не отмены запроса.
/// Несогласованная сборка повторяется в пределах прежнего лимита модели — восемь
/// попыток. Публикация результата и раскрытие секций остаются у модели.
Future<ActionDayAssemblyResult> assembleActionDaySnapshot({
  required CalendarDate date,
  required int incompleteItemCount,
  required int completedItemCount,
  required Future<ActionDayPageResult> Function(ActionDayQuery query) readPage,
  required bool Function() isCurrent,
  required bool Function(GraphRevision revision) acceptsRevision,
}) async {
  const maxAttempts = 8;

  attempts:
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (!isCurrent()) return const ActionDayAssemblyCancelled();
    final sections = <_SectionAssembly>[];
    for (final (section, target) in [
      (ActionDaySection.incomplete, incompleteItemCount),
      (ActionDaySection.completed, completedItemCount),
    ]) {
      final result = await _readPage(
        readPage,
        ActionDayQuery(date: date, section: section),
      );
      if (!isCurrent()) return const ActionDayAssemblyCancelled();
      switch (result) {
        case GraphResultSuccess(value: final ActionDayFirstPage page):
          if (!acceptsRevision(page.revision) ||
              (sections.isNotEmpty &&
                  page.revision.compareTo(sections.first.first.revision) !=
                      GraphRevisionOrder.same)) {
            continue attempts;
          }
          sections.add(_SectionAssembly(section, target, page));
        case GraphResultSuccess():
          return const ActionDayAssemblyFailed(ActionDayUnexpectedFailure());
        case GraphResultFailure(failure: ActionDaySnapshotExpired()):
          continue attempts;
        case GraphResultFailure(:final failure):
          return ActionDayAssemblyFailed(failure);
      }
    }

    final revision = sections.first.first.revision;
    for (final section in sections) {
      while (section.nextCursor != null &&
          section.items.length < section.target) {
        final result = await _readPage(
          readPage,
          ActionDayQuery(
            date: date,
            section: section.section,
            cursor: section.nextCursor,
          ),
        );
        if (!isCurrent()) return const ActionDayAssemblyCancelled();
        switch (result) {
          case GraphResultSuccess(value: final ActionDayContinuationPage page):
            if (page.revision.compareTo(revision) != GraphRevisionOrder.same ||
                !acceptsRevision(page.revision)) {
              continue attempts;
            }
            section.items.addAll(page.items);
            section.nextCursor = page.nextCursor;
          case GraphResultSuccess():
            return const ActionDayAssemblyFailed(ActionDayUnexpectedFailure());
          case GraphResultFailure(failure: ActionDaySnapshotExpired()):
            continue attempts;
          case GraphResultFailure(:final failure):
            return ActionDayAssemblyFailed(failure);
        }
      }
    }
    return ActionDayAssemblyReady(
      ActionDaySnapshot._(
        incomplete: sections[0].snapshot(),
        completed: sections[1].snapshot(),
        hasTimedActions: sections.first.first.hasTimedActions,
        revision: revision,
      ),
    );
  }
  return const ActionDayAssemblyFailed(ActionDayUnavailableFailure());
}

Future<ActionDayPageResult> _readPage(
  Future<ActionDayPageResult> Function(ActionDayQuery) read,
  ActionDayQuery query,
) async {
  try {
    return await read(query);
  } on Object {
    return const ActionDayPageError(ActionDayUnexpectedFailure());
  }
}

final class _SectionAssembly {
  _SectionAssembly(this.section, this.target, this.first)
    : items = [...first.items],
      nextCursor = first.nextCursor;

  final ActionDaySection section;
  final int target;
  final ActionDayFirstPage first;
  final List<ActionListItem> items;
  ActionDayCursor? nextCursor;

  ActionDaySectionSnapshot snapshot() => ActionDaySectionSnapshot._(
    items: items,
    totalCount: switch (section) {
      ActionDaySection.incomplete => first.incompleteCount,
      ActionDaySection.completed => first.completedCount,
    },
    nextCursor: nextCursor,
  );
}
