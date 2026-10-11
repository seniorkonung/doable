import '../application/graph_command_coordinator.dart';

/// Зафиксированные состав и текст одного сообщения общей поверхности.
final class GraphOperationMessagePlan {
  GraphOperationMessagePlan._({
    required Iterable<GraphOperationToken> coveredTokens,
    required this.message,
  }) : coveredTokens = List.unmodifiable(coveredTokens);

  final List<GraphOperationToken> coveredTokens;
  final String message;

  int get otherCount => coveredTokens.length - 1;
}

/// Выбирает сообщение из непустого списка [completions] в порядке завершений.
///
/// [messageFor] возвращает итоговый локализованный текст одного результата.
/// Самый ранний отказ объединяется только с отказами с тем же текстом.
/// При отсутствии отказов объединяются все успехи с текстом последнего.
GraphOperationMessagePlan planGraphOperationMessage(
  List<GraphCommandCompletion> completions,
  String Function(GraphCommandCompletion) messageFor,
) {
  final failureTokens = <GraphOperationToken>[];
  String? firstFailureMessage;
  for (final completion in completions) {
    if (!completion.isFailure) {
      continue;
    }
    final message = messageFor(completion);
    firstFailureMessage ??= message;
    if (message == firstFailureMessage) {
      failureTokens.add(completion.token);
    }
  }

  if (firstFailureMessage != null) {
    return GraphOperationMessagePlan._(
      coveredTokens: failureTokens,
      message: firstFailureMessage,
    );
  }
  return GraphOperationMessagePlan._(
    coveredTokens: completions.map((completion) => completion.token),
    message: messageFor(completions.last),
  );
}
