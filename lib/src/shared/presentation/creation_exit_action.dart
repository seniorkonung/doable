import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Смысл выхода, который модуль создания выводит из состояния своего потока.
enum CreationExitState {
  /// Команда ещё не принята либо завершилась отказом: создание можно отменить.
  cancellable,

  /// Принятая запись выполняется, в том числе после запроса выхода из потока.
  submitting,

  /// Создание завершено или покинуто; выполняющейся записи больше нет.
  terminal,
}

/// Общее действие дневного выбора и формы создания долговременной связи.
///
/// [onExit] всегда доступен, включая выполняющуюся запись и повтор выхода
/// после частичного отказа навигации. Принадлежность потока, прекращение
/// продолжения и закрытие его страниц обеспечивает вызывающий модуль.
/// Защищённое закрытие черновика намерения использует собственную процедуру.
class CreationExitAction extends StatelessWidget {
  const CreationExitAction({
    required this.state,
    required this.onExit,
    super.key,
  });

  final CreationExitState state;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (state) {
      CreationExitState.cancellable => l10n.creationCancelAction,
      CreationExitState.submitting ||
      CreationExitState.terminal => l10n.creationLeaveAction,
    };
    final explanation = switch (state) {
      CreationExitState.submitting => l10n.creationSavingContinues,
      CreationExitState.cancellable || CreationExitState.terminal => null,
    };

    // При недостатке высоты текст остаётся доступен через прокрутку:
    // https://api.flutter.dev/flutter/widgets/SingleChildScrollView-class.html
    return SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            // Подсказка и действие составляют один доступный узел:
            // https://api.flutter.dev/flutter/widgets/MergeSemantics-class.html
            child: Semantics(
              hint: explanation,
              child: TextButton(
                onPressed: onExit,
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
          ),
          if (explanation != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ExcludeSemantics(
                child: Text(explanation, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
