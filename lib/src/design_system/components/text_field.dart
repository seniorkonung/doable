import 'package:flutter/material.dart' hide TextField;
import 'package:flutter/material.dart' as material show TextField;

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Однострочное поле названия: плоскость `fill` без рамки и кольца фокуса,
/// где фокус показывает курсор. Текст хранит [controller] потребителя.
final class TextField extends StatelessWidget {
  static const double _materialGap = 4;
  static const double _startPadding = 14;
  static const double _leadingGap = 10;

  const TextField({
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.leading,
    required this.onChanged,
    this.error,
    super.key,
  });

  final TextEditingController controller;

  /// Заполнитель пустого поля, называющий, что в него пишется.
  final String placeholder;

  /// Доступное название поля; на экране не рисуется.
  final String label;

  /// Небольшая метка перед текстом, например точка цвета тега. Узла экранного
  /// диктора у неё быть не должно: поле называет [label].
  final Widget leading;

  final ValueChanged<String> onChanged;

  /// Ошибка ввода под полем; без неё строки ошибки нет.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final error = this.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: label,
          child: material.TextField(
            controller: controller,
            onChanged: onChanged,
            style: DoableType.action.copyWith(color: colors.ink),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: DoableType.action.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
              // Плотное поле снимает нижний предел Material в 48: строка
              // `action` высотой 22 с отступами по 13 даёт 48, а с крупным
              // шрифтом поле растёт.
              isDense: true,
              // Material 3 сам ставит 4 между меткой и текстом и ещё 4 у
              // конца заполненного поля, поэтому оба отступа добирают до
              // макета своими значениями.
              contentPadding: const EdgeInsetsDirectional.only(
                top: 13,
                bottom: 13,
                end: DoableMetrics.space3 - _materialGap,
              ),
              prefixIcon: Padding(
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
              child: Text(
                error,
                style: DoableType.hint.copyWith(color: colors.danger),
              ),
            ),
          ),
      ],
    );
  }
}
