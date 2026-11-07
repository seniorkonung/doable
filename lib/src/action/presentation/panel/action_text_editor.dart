import 'dart:async';

import 'package:flutter/material.dart' hide Action, TextField;

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../intention/domain/intention_text.dart';
import '../../application/action_command.dart';
import '../../domain/action.dart';
import '../../domain/action_text.dart';

/// Поле, которое получает фокус при открытии изменения.
enum ActionTextField { title, description }

/// Тексты обоих полей так, как они введены.
typedef ActionTextDraft = ({String title, String description});

/// Результат проверки введённых текстов на границе ввода: либо правка обоих
/// полей предметными типами, либо отказ по каждому полю.
sealed class ActionTextInput {
  const ActionTextInput();
}

final class ActionTextAccepted extends ActionTextInput {
  const ActionTextAccepted(this.patch);

  final ActionFieldsPatch patch;
}

/// Отказ проверки. Живёт до следующего ввода; новый отказ — новый объект,
/// поэтому поле показывается заново, даже если причины те же.
final class ActionTextRejected extends ActionTextInput {
  const ActionTextRejected({this.title, this.description});

  final IntentionTextValidationReason? title;
  final IntentionTextValidationReason? description;
}

/// Открытое изменение названия и описания: тексты при открытии, введённые
/// тексты и последний отказ проверки.
final class ActionTextEdit {
  const ActionTextEdit._({
    required this.focus,
    required this.opened,
    required this.current,
    required this.rejected,
  });

  factory ActionTextEdit.open(Action action, ActionTextField focus) {
    final draft = (
      title: action.title.value,
      description: action.description?.value ?? '',
    );
    return ActionTextEdit._(
      focus: focus,
      opened: draft,
      current: draft,
      rejected: null,
    );
  }

  final ActionTextField focus;
  final ActionTextDraft opened;
  final ActionTextDraft current;
  final ActionTextRejected? rejected;

  bool get isChanged => current != opened;

  /// Сохранить можно, пока что-то изменено и название не пусто после
  /// обрезки.
  bool get canSave => isChanged && !IntentionText.isBlankTitle(current.title);

  ActionTextEdit withDraft(ActionTextDraft draft) => ActionTextEdit._(
    focus: focus,
    opened: opened,
    current: draft,
    rejected: null,
  );

  ActionTextEdit withRejected(ActionTextRejected rejected) => ActionTextEdit._(
    focus: focus,
    opened: opened,
    current: current,
    rejected: rejected,
  );

  /// Превращает введённые тексты в правку обоих полей. Пробельное описание
  /// означает отсутствие описания.
  ActionTextInput parse() {
    ActionTitle? title;
    IntentionTextValidationReason? titleReason;
    try {
      title = ActionTitle(current.title);
    } on IntentionTextValidationException catch (exception) {
      titleReason = exception.failure.reason;
    }
    ActionDescription? description;
    IntentionTextValidationReason? descriptionReason;
    try {
      description = ActionDescription.fromInput(current.description);
    } on IntentionTextValidationException catch (exception) {
      descriptionReason = exception.failure.reason;
    }
    if (title != null && descriptionReason == null) {
      return ActionTextAccepted(
        ActionFieldsPatch(
          title: ActionFieldSet(title),
          description: ActionFieldSet(description),
        ),
      );
    }
    return ActionTextRejected(
      title: titleReason,
      description: descriptionReason,
    );
  }
}

/// Поля названия и описания изменения.
///
/// Поля владеют своими текстом и фокусом, а панель получает каждое изменение
/// текста через [onChanged]. Поле, по которому нажали, получает фокус при
/// открытии, а курсор стоит в конце текста.
final class ActionTextEditor extends StatefulWidget {
  const ActionTextEditor({
    required this.edit,
    required this.readOnly,
    required this.onChanged,
    super.key,
  });

  final ActionTextEdit edit;

  /// Тексты не меняются вводом, пока идёт запись.
  final bool readOnly;

  final ValueChanged<ActionTextDraft> onChanged;

  @override
  State<ActionTextEditor> createState() => _ActionTextEditorState();
}

final class _ActionTextEditorState extends State<ActionTextEditor> {
  static const _descriptionMinLines = 5;
  static const _descriptionMaxLines = 13;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();

  /// Поле вместе с отказом проверки под ним.
  final _titleKey = GlobalKey();
  final _descriptionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final current = widget.edit.current;
    _titleController = _controllerWithCursorAtEnd(current.title);
    _descriptionController = _controllerWithCursorAtEnd(current.description);
  }

  static TextEditingController _controllerWithCursorAtEnd(String text) =>
      TextEditingController.fromValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );

  @override
  void didUpdateWidget(ActionTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rejected = widget.edit.rejected;
    if (rejected != null && !identical(rejected, oldWidget.edit.rejected)) {
      _revealRejected(rejected);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _changed() => widget.onChanged((
    title: _titleController.text,
    description: _descriptionController.text,
  ));

  /// Прокручивает к первому отказу проверки после его кадра: под длинным
  /// текстом или над клавиатурой он оказался бы вне видимой части.
  ///
  /// Фокус снимается, иначе вернувшаяся клавиатура прокрутит обратно к
  /// каретке.
  void _revealRejected(ActionTextRejected rejected) {
    _titleFocus.unfocus();
    _descriptionFocus.unfocus();
    final key = rejected.title != null ? _titleKey : _descriptionKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = key.currentContext;
      if (!mounted || field == null) return;
      unawaited(
        Scrollable.ensureVisible(
          field,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final rejected = widget.edit.rejected;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        DoableMetrics.space3,
        DoableMetrics.space5,
        DoableMetrics.space4,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: _titleKey,
              child: TextField.multiline(
                controller: _titleController,
                focusNode: _titleFocus,
                placeholder: localizations.actionTextEditNameLabel,
                label: localizations.actionTextEditNameLabel,
                kind: TextFieldKind.name,
                autofocus: widget.edit.focus == ActionTextField.title,
                readOnly: widget.readOnly,
                onChanged: (_) => _changed(),
                error: switch (rejected?.title) {
                  IntentionTextValidationReason.empty => Text(
                    localizations.editorTitleEmpty,
                  ),
                  IntentionTextValidationReason.tooLong => Text(
                    localizations.editorTitleTooLong,
                  ),
                  IntentionTextValidationReason.invalidUnicodeRepertoire =>
                    Text(localizations.editorTitleInvalidUnicode),
                  null => null,
                },
              ),
            ),
            const SizedBox(height: DoableMetrics.space2),
            KeyedSubtree(
              key: _descriptionKey,
              child: TextField.multiline(
                controller: _descriptionController,
                focusNode: _descriptionFocus,
                placeholder: localizations.detailsAddDescription,
                label: localizations.actionTextEditDescriptionLabel,
                minLines: _descriptionMinLines,
                maxLines: _descriptionMaxLines,
                autofocus: widget.edit.focus == ActionTextField.description,
                readOnly: widget.readOnly,
                onChanged: (_) => _changed(),
                error: switch (rejected?.description) {
                  IntentionTextValidationReason.tooLong => Text(
                    localizations.editorDescriptionTooLong,
                  ),
                  IntentionTextValidationReason.invalidUnicodeRepertoire =>
                    Text(localizations.editorDescriptionInvalidUnicode),
                  IntentionTextValidationReason.empty => Text(
                    localizations.actionDescriptionInvalid,
                  ),
                  null => null,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
