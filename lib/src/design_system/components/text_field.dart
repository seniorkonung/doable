import 'package:flutter/material.dart' hide TextField;
import 'package:flutter/material.dart' as material show TextField;

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

enum TextFieldKind { name, text }

/// Поле ввода: плоскость `fill` без рамки и кольца фокуса,
/// где фокус показывает курсор. Текст хранит [controller] потребителя.
final class TextField extends StatelessWidget {
  static const double _materialGap = 4;
  static const double _startPadding = 14;
  static const double _leadingGap = 10;

  const TextField({
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.onChanged,
    this.leading,
    this.autofocus = false,
    this.error,
    super.key,
  }) : _multiline = false,
       kind = TextFieldKind.name,
       minLines = 1,
       maxLines = 1;

  /// Растущее поле без метки перед текстом. Без [maxLines] текст
  /// переносится целиком; после предела прокручивается внутри поля.
  /// https://api.flutter.dev/flutter/material/TextField/minLines.html
  const TextField.multiline({
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.onChanged,
    this.kind = TextFieldKind.text,
    this.minLines = 1,
    this.maxLines,
    this.autofocus = false,
    this.error,
    super.key,
  }) : assert(minLines > 0),
       assert(maxLines == null || maxLines >= minLines),
       _multiline = true,
       leading = null;

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

  /// Запрашивает фокус при первом показе, если другое поле его не получило.
  final bool autofocus;

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: label,
          child: material.TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: maxLines,
            autofocus: autofocus,
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
