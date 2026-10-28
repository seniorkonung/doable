import 'package:flutter/material.dart';

import '../doable_icon.dart';
import 'option_row.dart';
import 'sheet.dart';

/// Пункт листа параметров.
final class OptionsMenuItem<T extends Object> {
  /// Доступный пункт: выбор закрывает лист и возвращает [value].
  /// [hint] называет последствия выбора.
  const OptionsMenuItem({
    required T this.value,
    required this.icon,
    required this.name,
    this.hint,
    this.tone = OptionRowTone.normal,
  });

  /// Пункт, которым сейчас нельзя воспользоваться: он остаётся на своём месте
  /// приглушённым, а [reason] называет, что мешает и что сделать сначала.
  const OptionsMenuItem.unavailable({
    required this.icon,
    required this.name,
    required String reason,
    this.tone = OptionRowTone.normal,
  }) : value = null,
       hint = reason;

  /// Значение доступного пункта; у недоступного его нет.
  final T? value;
  final DoableIconData icon;
  final String name;
  final String? hint;
  final OptionRowTone tone;
}

/// Лист параметров одного предмета: заголовок называет вид предмета, а пункты
/// стоят в переданном порядке.
///
/// Открывается через [showDoableSheet] с тем же типом [T]. Выбор доступного
/// пункта закрывает лист, и показ возвращает значение пункта уже после
/// закрытия, поэтому действие начинается без открытого листа. Закрытие без
/// выбора возвращает null.
final class OptionsMenu<T extends Object> extends StatelessWidget {
  const OptionsMenu(
    this.sheet, {
    required this.title,
    required this.items,
    super.key,
  });

  final SheetPresentation sheet;

  /// Вид предмета, например «Намерение»; им же диктор называет лист.
  final String title;
  final List<OptionsMenuItem<T>> items;

  @override
  Widget build(BuildContext context) => Sheet(
    sheet,
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          OptionRow(
            icon: item.icon,
            name: item.name,
            hint: item.hint,
            tone: item.tone,
            onPressed: switch (item.value) {
              final value? => () => Navigator.of(context).pop(value),
              null => null,
            },
          ),
      ],
    ),
  );
}
