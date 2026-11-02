import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'button.dart';
import 'edge_overhang.dart';

/// Одно поле выбора в строке: подпись слева, а справа либо пилюля со значком и
/// значением, либо виджет потребителя.
///
/// Строка не ниже `tap-min` и растёт вместе с текстом. Подпись — `row` цвета
/// `ink`, а между ней и правым элементом стоит `space-3`. Строки идут друг
/// за другом без зазора и без разделителей. Пилюля — тихая кнопка размера sm
/// из [Button.quietSmallIcon]; она переносит значение, если ему не хватает
/// места. Подпись диктору не читается: поле называет [valueLabel] пилюли или
/// сам виджет потребителя.
///
/// Тексты, значок и доступное название задаёт потребитель.
final class DetailRow extends StatelessWidget {
  /// Пилюля со значком и значением. [valueLabel] называет поле, его полное
  /// значение и действие, например «Дата: четверг, 8 октября 2026. Изменить
  /// дату». Без [onPressed] пилюля недоступна, а значение остаётся на экране
  /// и называется диктору.
  DetailRow({
    required this.label,
    required DoableIconData icon,
    required String value,
    required String valueLabel,
    VoidCallback? onPressed,
    super.key,
  }) : _control = _PillControl(
         icon: icon,
         value: value,
         valueLabel: valueLabel,
         onPressed: onPressed,
       );

  /// Виджет потребителя на месте пилюли, например выбор приоритета. [shift] —
  /// на сколько он выходит за правый край строки; лишняя полоса принимает
  /// касания, пока родитель шире строки на неё.
  DetailRow.slot({
    required this.label,
    required Widget child,
    double shift = 0,
    super.key,
  }) : _control = _SlotControl(child: child, shift: shift);

  /// Название поля слева: «Дата», «Время», «Приоритет».
  final String label;

  final _Control _control;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final control = _control;

    return EdgeOverhang(
      end: switch (control) {
        _PillControl() => 0,
        _SlotControl(:final shift) => shift,
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
        child: Row(
          spacing: DoableMetrics.space3,
          children: [
            ExcludeSemantics(
              child: Text(
                label,
                style: DoableType.row.copyWith(color: colors.ink),
              ),
            ),
            // Правому элементу достаётся всё, что осталось после подписи, а
            // высоту строки задаёт он сам: `Align` без `heightFactor` занял бы
            // всю доступную высоту.
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                heightFactor: 1,
                child: switch (control) {
                  _PillControl(
                    :final icon,
                    :final value,
                    :final valueLabel,
                    :final onPressed,
                  ) =>
                    Button.quietSmallIcon(
                      label: value,
                      icon: icon,
                      semanticLabel: valueLabel,
                      onPressed: onPressed,
                    ),
                  _SlotControl(:final child) => child,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Правый элемент строки: пилюля или виджет потребителя.
sealed class _Control {
  const _Control();
}

final class _PillControl extends _Control {
  const _PillControl({
    required this.icon,
    required this.value,
    required this.valueLabel,
    required this.onPressed,
  });

  final DoableIconData icon;
  final String value;
  final String valueLabel;
  final VoidCallback? onPressed;
}

final class _SlotControl extends _Control {
  const _SlotControl({required this.child, required this.shift});

  final Widget child;
  final double shift;
}
