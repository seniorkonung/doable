import '../application/graph_command_coordinator.dart';

/// Итоговое сообщение одного результата.
final class GraphOperationMessage {
  const GraphOperationMessage(this.text, {this.action});

  final String text;

  /// Действие сообщения; объединение результатов его не сравнивает.
  final GraphOperationMessageAction? action;
}

/// Действие, которое сообщение общей поверхности предлагает пользователю.
final class GraphOperationMessageAction {
  const GraphOperationMessageAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final void Function() onPressed;
}

/// Зафиксированные состав и текст одного сообщения общей поверхности.
final class GraphOperationMessagePlan {
  GraphOperationMessagePlan._({
    required Iterable<GraphOperationToken> coveredTokens,
    required this.message,
  }) : coveredTokens = List.unmodifiable(coveredTokens);

  final List<GraphOperationToken> coveredTokens;

  /// Сообщение результата, текст которого показывается.
  final GraphOperationMessage message;

  int get otherCount => coveredTokens.length - 1;
}

/// Выбирает сообщение из непустого списка [completions] в порядке завершений.
///
/// [messageFor] возвращает итоговое локализованное сообщение одного
/// результата. Самый ранний отказ объединяется только с отказами с тем же
/// текстом. При отсутствии отказов объединяются все успехи с сообщением
/// последнего.
GraphOperationMessagePlan planGraphOperationMessage(
  List<GraphCommandCompletion> completions,
  GraphOperationMessage Function(GraphCommandCompletion) messageFor,
) {
  final failureTokens = <GraphOperationToken>[];
  GraphOperationMessage? firstFailureMessage;
  for (final completion in completions) {
    if (!completion.isFailure) {
      continue;
    }
    final message = messageFor(completion);
    firstFailureMessage ??= message;
    if (message.text == firstFailureMessage.text) {
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
