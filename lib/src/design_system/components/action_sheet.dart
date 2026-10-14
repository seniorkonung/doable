import 'package:flutter/widgets.dart';

import 'option_row.dart';
import 'sheet.dart';

/// Лист с пояснением и вариантами, расположенными без промежутков.
/// Выбранность, начальный фокус и обработчики строк задаёт потребитель.
final class ActionSheet extends StatelessWidget {
  const ActionSheet({
    required this.title,
    required this.text,
    required this.options,
    super.key,
  });

  final String title;
  final String text;
  final List<OptionRow> options;

  @override
  Widget build(BuildContext context) => Sheet(
    title: title,
    text: text,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: options,
    ),
  );
}
