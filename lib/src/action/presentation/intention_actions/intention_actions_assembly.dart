import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/action_list_item.dart';
import '../../application/intention_actions.dart';

sealed class IntentionActionsAssemblyResult {
  const IntentionActionsAssemblyResult();
}

/// Числа и строки выбранной плитки получены на одной ревизии.
final class IntentionActionsAssembled extends IntentionActionsAssemblyResult {
  const IntentionActionsAssembled({
    required this.role,
    required this.counts,
    required this.revision,
    required this.items,
    required this.nextCursor,
  });

  final IntentionActionRole role;
  final IntentionActionCounts counts;
  final GraphRevision revision;
  final List<ActionListItem> items;
  final IntentionActionsCursor? nextCursor;
}

final class IntentionActionsAssemblyFailed
    extends IntentionActionsAssemblyResult {
  const IntentionActionsAssemblyFailed(this.failure);

  final IntentionActionsReadFailure failure;
}

final class IntentionActionsAssemblyCancelled
    extends IntentionActionsAssemblyResult {
  const IntentionActionsAssemblyCancelled();
}

/// Читает первую порцию плитки [role] и дочитывает продолжения, пока не
/// наберётся [itemCount] строк или не кончится список. Без [role] плитку
/// выбирают числа первого чтения: плитка с наибольшим числом, а если она не
/// корневая, её первая порция читается заново.
///
/// Ревизии всех порций совпадают. Несогласованная сборка повторяется
/// в пределах восьми попыток.
///
/// [isCurrent] проверяет, что результат ещё нужен: отмена не прерывает
/// начатое чтение, а отбрасывает его ответ. [acceptsRevision] отклоняет
/// ревизии старше подтверждённых изменений, известных модели.
Future<IntentionActionsAssemblyResult> assembleIntentionActions({
  required IntentionId intentionId,
  required IntentionActionRole? role,
  required int itemCount,
  required int pageSize,
  required Future<IntentionActionsPageResult> Function(
    IntentionActionsQuery query,
  )
  readPage,
  required bool Function() isCurrent,
  required bool Function(GraphRevision revision) acceptsRevision,
}) async {
  const maxAttempts = 8;

  Future<IntentionActionsPageResult> read(
    IntentionActionRole role, [
    IntentionActionsCursor? cursor,
  ]) async {
    try {
      return await readPage(
        IntentionActionsQuery(
          intentionId: intentionId,
          role: role,
          pageSize: pageSize,
          cursor: cursor,
        ),
      );
    } on Object {
      // Неизвестная причина отказа не выдаётся за отсутствие действий.
      return const IntentionActionsPageError(
        IntentionActionsUnexpectedFailure(),
      );
    }
  }

  attempts:
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (!isCurrent()) return const IntentionActionsAssemblyCancelled();

    var selected = role ?? IntentionActionRole.root;
    var firstResult = await read(selected);
    if (!isCurrent()) return const IntentionActionsAssemblyCancelled();
    if (role == null) {
      if (firstResult
          case GraphResultSuccess(
            value: IntentionActionsFirstPage(:final counts),
          )
          when counts.busiestRole != selected) {
        selected = counts.busiestRole;
        firstResult = await read(selected);
        if (!isCurrent()) return const IntentionActionsAssemblyCancelled();
      }
    }

    final IntentionActionsFirstPage first;
    switch (firstResult) {
      case GraphResultSuccess(value: final IntentionActionsFirstPage page):
        if (!acceptsRevision(page.revision)) continue attempts;
        first = page;
      case GraphResultSuccess():
        return const IntentionActionsAssemblyFailed(
          IntentionActionsUnexpectedFailure(),
        );
      case GraphResultFailure(failure: IntentionActionsSnapshotExpired()):
        continue attempts;
      case GraphResultFailure(:final failure):
        return IntentionActionsAssemblyFailed(failure);
    }

    final items = [...first.items];
    var cursor = first.nextCursor;
    while (cursor != null && items.length < itemCount) {
      final result = await read(selected, cursor);
      if (!isCurrent()) return const IntentionActionsAssemblyCancelled();
      switch (result) {
        case GraphResultSuccess(
          value: final IntentionActionsContinuationPage next,
        ):
          if (next.revision.compareTo(first.revision) !=
                  GraphRevisionOrder.same ||
              !acceptsRevision(next.revision)) {
            continue attempts;
          }
          items.addAll(next.items);
          cursor = next.nextCursor;
        case GraphResultSuccess():
          return const IntentionActionsAssemblyFailed(
            IntentionActionsUnexpectedFailure(),
          );
        case GraphResultFailure(failure: IntentionActionsSnapshotExpired()):
          continue attempts;
        case GraphResultFailure(:final failure):
          return IntentionActionsAssemblyFailed(failure);
      }
    }
    return IntentionActionsAssembled(
      role: selected,
      counts: first.counts,
      revision: first.revision,
      items: items,
      nextCursor: cursor,
    );
  }
  return const IntentionActionsAssemblyFailed(
    IntentionActionsUnavailableFailure(),
  );
}
