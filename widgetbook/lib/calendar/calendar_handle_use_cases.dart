import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

List<WidgetbookUseCase> calendarHandleUseCases() => [
  for (final expanded in [false, true])
    WidgetbookUseCase(
      name: expanded ? 'Раскрытый календарь' : 'Свёрнутый календарь',
      builder: (context) =>
          _HandlePreview(key: ValueKey(expanded), initiallyExpanded: expanded),
    ),
];

class _HandlePreview extends StatefulWidget {
  const _HandlePreview({super.key, required this.initiallyExpanded});

  final bool initiallyExpanded;

  @override
  State<_HandlePreview> createState() => _HandlePreviewState();
}

class _HandlePreviewState extends State<_HandlePreview> {
  late double _progress = widget.initiallyExpanded ? 1 : 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 390,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space3),
          children: [
            CalendarHandle(
              isExpanded: _progress == 1,
              expansionProgress: _progress,
              semanticLabel: _progress == 1
                  ? 'Свернуть календарь'
                  : 'Раскрыть календарь',
              onTap: () => setState(() => _progress = _progress == 1 ? 0 : 1),
            ),
            const SizedBox(height: DoableMetrics.space4),
            const Text('Степень раскрытия ручки'),
            Slider(
              value: _progress,
              onChanged: (value) => setState(() => _progress = value),
            ),
          ],
        ),
      ),
    ),
  );
}
