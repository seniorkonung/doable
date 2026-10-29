import 'package:flutter/material.dart' hide TextField;
import 'package:flutter/material.dart' as material show TextField;
import 'package:flutter/services.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

enum TextFieldKind { name, text }

/// Заменяет каждый перенос строки во введённом или вставленном тексте одним
/// пробелом: название не принимает переносов, но переносится по ширине поля.
final TextInputFormatter lineBreakToSpaceFormatter =
    FilteringTextInputFormatter.deny(
      RegExp(r'\r\n|[\r\n]'),
      replacementString: ' ',
    );

/// Плоскость `fill` без рамки для текста: поле ввода или сохранённый текст,
/// который открывает свою правку.
sealed class TextField extends StatelessWidget {
  const TextField._({super.key});

  /// Однострочное поле ввода, где фокус показывает курсор. Текст хранит
  /// `controller` потребителя.
  const factory TextField({
    required TextEditingController controller,
    required String placeholder,
    required String label,
    required ValueChanged<String> onChanged,
    Widget? leading,
    FocusNode? focusNode,
    bool autofocus,
    bool readOnly,
    Widget? error,
    Key? key,
  }) = _InputTextField;

  /// Растущее поле без метки перед текстом. Без `maxLines` текст
  /// переносится целиком; после предела прокручивается внутри поля.
  /// Название не принимает переносов строк: клавиша ввода переводит фокус
  /// к следующему полю.
  /// https://api.flutter.dev/flutter/material/TextField/minLines.html
  const factory TextField.multiline({
    required TextEditingController controller,
    required String placeholder,
    required String label,
    required ValueChanged<String> onChanged,
    TextFieldKind kind,
    int minLines,
    int? maxLines,
    FocusNode? focusNode,
    bool autofocus,
    bool readOnly,
    Widget? error,
    Key? key,
  }) = _InputTextField.multiline;

  /// Сохранённый текст там, где его читают: кнопка с видом поля, которая
  /// показывает [value] целиком с переносами строк, а без текста —
  /// заполнитель. Нажатие открывает правку текста.
  ///
  /// [label] называет действие нажатия. Пока [onOpen] не задан, кнопка
  /// выключена.
  const factory TextField.saved({
    required String value,
    required String placeholder,
    required String label,
    required VoidCallback? onOpen,
    Key? key,
  }) = _SavedTextField;
}

final class _InputTextField extends TextField {
  static const double _materialGap = 4;
  static const double _startPadding = 14;
  static const double _leadingGap = 10;

  const _InputTextField({
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.onChanged,
    this.leading,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.error,
    super.key,
  }) : _multiline = false,
       kind = TextFieldKind.name,
       minLines = 1,
       maxLines = 1,
       super._();

  const _InputTextField.multiline({
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.onChanged,
    this.kind = TextFieldKind.text,
    this.minLines = 1,
    this.maxLines,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.error,
    super.key,
  }) : assert(minLines > 0),
       assert(maxLines == null || maxLines >= minLines),
       _multiline = true,
       leading = null,
       super._();

  final TextEditingController controller;

  /// Заполнитель пустого поля, называющий, что в него пишется.
  final String placeholder;

  /// Доступное название поля; на экране не рисуется.
  final String label;

  /// Небольшая метка перед текстом, например точка цвета тега. Узла экранного
  /// диктора у неё быть не должно: поле называет [label].
  final Widget? leading;

  final TextFieldKind kind;
  final int minLines;
  final int? maxLines;

  /// Фокус поля, если потребитель управляет им сам.
  final FocusNode? focusNode;

  /// Запрашивает фокус при первом показе, если другое поле его не получило.
  final bool autofocus;

  /// Текст не меняется вводом, например пока отправлен черновик: поле не
  /// показывает текст, которого нет в принятой команде.
  final bool readOnly;

  final bool _multiline;

  final ValueChanged<String> onChanged;

  /// Ошибка под полем, наследующая `hint` и `danger` и объявляемая диктором.
  /// Потребитель может передать собственный renderer предъявления отказа.
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final error = this.error;
    final style = switch (kind) {
      TextFieldKind.name => DoableType.action,
      TextFieldKind.text => DoableType.field,
    };
    final verticalPadding = kind == TextFieldKind.name ? 13.0 : 11.0;
    final startPadding = _multiline ? DoableMetrics.space3 : _startPadding;
    final isSingleParagraph = _multiline && kind == TextFieldKind.name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: label,
          child: material.TextField(
            controller: controller,
            onChanged: onChanged,
            focusNode: focusNode,
            minLines: minLines,
            maxLines: maxLines,
            autofocus: autofocus,
            readOnly: readOnly,
            // Растущее поле по умолчанию берёт многострочную клавиатуру с
            // клавишей переноса:
            // https://api.flutter.dev/flutter/material/TextField/keyboardType.html
            keyboardType: isSingleParagraph ? TextInputType.text : null,
            textInputAction: isSingleParagraph ? TextInputAction.next : null,
            inputFormatters: isSingleParagraph
                ? [lineBreakToSpaceFormatter]
                : null,
            style: style.copyWith(color: colors.ink),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: style.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
              // Плотное поле снимает нижний предел Material в 48: строка
              // `action` высотой 22 с отступами по 13 даёт 48, а с крупным
              // шрифтом поле растёт.
              isDense: true,
              // Material 3 добавляет inputGap=4 с обеих сторон текста,
              // в том числе без метки. Вычитаем его из отступов макета.
              contentPadding: EdgeInsetsDirectional.only(
                start: leading == null ? startPadding - _materialGap : 0,
                top: verticalPadding,
                bottom: verticalPadding,
                end: DoableMetrics.space3 - _materialGap,
              ),
              prefixIcon: leading == null
                  ? null
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: _startPadding,
                        end: _leadingGap - _materialGap,
                      ),
                      child: leading,
                    ),
              prefixIconConstraints: const BoxConstraints(),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space1,
              6,
              DoableMetrics.space1,
              0,
            ),
            child: Semantics(
              liveRegion: true,
              child: DefaultTextStyle.merge(
                style: DoableType.hint.copyWith(color: colors.danger),
                child: error,
              ),
            ),
          ),
      ],
    );
  }
}

final class _SavedTextField extends TextField {
  static const _radius = BorderRadius.all(
    Radius.circular(DoableMetrics.radiusSm),
  );

  const _SavedTextField({
    required this.value,
    required this.placeholder,
    required this.label,
    required this.onOpen,
    super.key,
  }) : super._();

  final String value;
  final String placeholder;
  final String label;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final isEmpty = value.isEmpty;
    // Роль кнопки и готовое название принадлежат одному узлу:
    // https://api.flutter.dev/flutter/widgets/Semantics-class.html
    return Semantics(
      container: true,
      button: true,
      enabled: onOpen != null,
      label: label,
      onTap: onOpen,
      // Плоскость и отклик нажатия рисуются в порядке потомков, поэтому
      // область прокрутки их обрезает. На Material предка они рисовались бы
      // под всем его содержимым и без этой обрезки:
      // https://api.flutter.dev/flutter/material/InkWell-class.html
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.fill, borderRadius: _radius),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onOpen,
            excludeFromSemantics: true,
            mouseCursor: onOpen == null ? null : SystemMouseCursors.text,
            borderRadius: _radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: double.infinity,
                minHeight: DoableMetrics.tapMin,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DoableMetrics.space3,
                  vertical: 11,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    isEmpty ? placeholder : value,
                    softWrap: true,
                    style: DoableType.field.copyWith(
                      color: isEmpty ? colors.muted : colors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
