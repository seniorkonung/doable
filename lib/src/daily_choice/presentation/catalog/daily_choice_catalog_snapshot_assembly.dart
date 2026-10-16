import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';

/// Загруженная часть секции и её полная сводка на ревизии общей пары.
final class DailyChoiceCatalogSectionSnapshot {
  DailyChoiceCatalogSectionSnapshot._({
    required List<DailyChoiceCatalogItem> items,
    required this.totalCount,
    required this.hasTimedChoices,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<DailyChoiceCatalogItem> items;
  final int totalCount;
  final bool hasTimedChoices;
  final DailyChoiceCatalogCursor? nextCursor;
}

/// Конструктор закрыт: пару создаёт только сборка порций одной ревизии.
final class DailyChoiceCatalogSnapshot {
  const DailyChoiceCatalogSnapshot._({
    required this.incomplete,
    required this.completed,
    required this.revision,
  });

  final DailyChoiceCatalogSectionSnapshot incomplete;
  final DailyChoiceCatalogSectionSnapshot completed;
  final GraphRevision revision;
}

sealed class DailyChoiceCatalogAssemblyResult {
  const DailyChoiceCatalogAssemblyResult();
}

final class DailyChoiceCatalogAssemblyReady
    extends DailyChoiceCatalogAssemblyResult {
  const DailyChoiceCatalogAssemblyReady(this.snapshot);

  final DailyChoiceCatalogSnapshot snapshot;
}

final class DailyChoiceCatalogAssemblyFailed
    extends DailyChoiceCatalogAssemblyResult {
  const DailyChoiceCatalogAssemblyFailed(this.failure);

  final DailyChoiceCatalogReadFailure failure;
}

final class DailyChoiceCatalogAssemblyCancelled
    extends DailyChoiceCatalogAssemblyResult {
  const DailyChoiceCatalogAssemblyCancelled();
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
Future<DailyChoiceCatalogAssemblyResult> assembleDailyChoiceCatalogSnapshot({
  required CalendarDate date,
  required int incompleteItemCount,
  required int completedItemCount,
  required Future<DailyChoiceCatalogPageResult> Function(
    DailyChoiceCatalogQuery query,
  )
  readPage,
  required bool Function() isCurrent,
  required bool Function(GraphRevision revision) acceptsRevision,
}) async {
  const maxAttempts = 8;

  attempts:
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (!isCurrent()) return const DailyChoiceCatalogAssemblyCancelled();
    final sections = <_SectionAssembly>[];
    for (final (isCompleted, target) in [
      (false, incompleteItemCount),
      (true, completedItemCount),
    ]) {
      final result = await _readPage(
        readPage,
        DailyChoiceCatalogQuery(date: date, isCompleted: isCompleted),
      );
      if (!isCurrent()) return const DailyChoiceCatalogAssemblyCancelled();
      switch (result) {
        case GraphResultSuccess(value: final DailyChoiceCatalogFirstPage page):
          if (!acceptsRevision(page.revision) ||
              (sections.isNotEmpty &&
                  page.revision.compareTo(sections.first.first.revision) !=
                      GraphRevisionOrder.same)) {
            continue attempts;
          }
          sections.add(_SectionAssembly(isCompleted, target, page));
        case GraphResultSuccess():
          return const DailyChoiceCatalogAssemblyFailed(
            DailyChoiceCatalogUnexpectedFailure(),
          );
        case GraphResultFailure(failure: DailyChoiceCatalogSnapshotExpired()):
          continue attempts;
        case GraphResultFailure(:final failure):
          return DailyChoiceCatalogAssemblyFailed(failure);
      }
    }

    final revision = sections.first.first.revision;
    for (final section in sections) {
      while (section.nextCursor != null &&
          section.items.length < section.target) {
        final result = await _readPage(
          readPage,
          DailyChoiceCatalogQuery(
            date: date,
            isCompleted: section.isCompleted,
            cursor: section.nextCursor,
          ),
        );
        if (!isCurrent()) return const DailyChoiceCatalogAssemblyCancelled();
        switch (result) {
          case GraphResultSuccess(
            value: final DailyChoiceCatalogContinuationPage page,
          ):
            if (page.revision.compareTo(revision) != GraphRevisionOrder.same ||
                !acceptsRevision(page.revision)) {
              continue attempts;
            }
            section.items.addAll(page.items);
            section.nextCursor = page.nextCursor;
          case GraphResultSuccess():
            return const DailyChoiceCatalogAssemblyFailed(
              DailyChoiceCatalogUnexpectedFailure(),
            );
          case GraphResultFailure(failure: DailyChoiceCatalogSnapshotExpired()):
            continue attempts;
          case GraphResultFailure(:final failure):
            return DailyChoiceCatalogAssemblyFailed(failure);
        }
      }
    }
    return DailyChoiceCatalogAssemblyReady(
      DailyChoiceCatalogSnapshot._(
        incomplete: sections[0].snapshot(),
        completed: sections[1].snapshot(),
        revision: revision,
      ),
    );
  }
  return const DailyChoiceCatalogAssemblyFailed(
    DailyChoiceCatalogUnavailableFailure(),
  );
}

Future<DailyChoiceCatalogPageResult> _readPage(
  Future<DailyChoiceCatalogPageResult> Function(DailyChoiceCatalogQuery) read,
  DailyChoiceCatalogQuery query,
) async {
  try {
    return await read(query);
  } on Object {
    return const DailyChoiceCatalogPageError(
      DailyChoiceCatalogUnexpectedFailure(),
    );
  }
}

final class _SectionAssembly {
  _SectionAssembly(this.isCompleted, this.target, this.first)
    : items = [...first.items],
      nextCursor = first.nextCursor;

  final bool isCompleted;
  final int target;
  final DailyChoiceCatalogFirstPage first;
  final List<DailyChoiceCatalogItem> items;
  DailyChoiceCatalogCursor? nextCursor;

  DailyChoiceCatalogSectionSnapshot snapshot() =>
      DailyChoiceCatalogSectionSnapshot._(
        items: items,
        totalCount: first.totalCount,
        hasTimedChoices: first.hasTimedChoices,
        nextCursor: nextCursor,
      );
}
