import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Однострочное поле поиска: список сужается с каждым введённым символом,
/// а отдельной кнопки поиска нет. Текст хранит [controller] потребителя.
final class SearchField extends StatelessWidget {
  static const double _materialIconGap = 4;
  static const double _endPadding = 6;

  const SearchField({
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.clearLabel,
    required this.onChanged,
    this.error,
    super.key,
  });

  final TextEditingController controller;

  /// Заполнитель пустого поля, называющий, что ищется.
  final String placeholder;

  /// Доступное название поля; на экране не рисуется.
  final String label;

  /// Доступное название крестика очистки.
  final String clearLabel;

  /// Получает каждое изменение текста, в том числе пустой текст после
  /// очистки крестиком.
  final ValueChanged<String> onChanged;

  /// Ошибка ввода под полем; без неё строки ошибки нет.
  final String? error;

  void _clear() {
    controller.clear();
    onChanged('');
  }

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
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: DoableType.field.copyWith(color: colors.ink),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: DoableType.field.copyWith(color: colors.muted),
              // Плотное поле снимает нижний предел Material в 48: строка
              // `field` высотой 22 с отступами по 11 даёт `tap-min`, а с
              // крупным шрифтом поле растёт.
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              // Material 3 сам ставит 4 между значками и текстом, поэтому
              // значки добирают до `space-2` своими отступами.
              prefixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: DoableMetrics.space3,
                  end: DoableMetrics.space2 - _materialIconGap,
                ),
                child: DoableIcon(
                  DoableIconData.search,
                  size: 20,
                  color: colors.muted,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox(width: _endPadding - _materialIconGap)
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: DoableMetrics.space2 - _materialIconGap,
                          end: _endPadding,
                        ),
                        child: _ClearButton(
                          label: clearLabel,
                          onPressed: _clear,
                        ),
                      ),
              ),
              suffixIconConstraints: const BoxConstraints(),
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

/// Крестик очистки: диск `grip` 20 с крестиком 12 в области нажатия 32.
final class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 32,
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.grip,
              ),
              child: DoableIcon(
                DoableIconData.clear,
                size: 12,
                color: colors.fill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
