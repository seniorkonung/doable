import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

List<WidgetbookUseCase> noticeUseCases() => [
  WidgetbookUseCase(
    name: 'Отказ без действия',
    builder: (context) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          child: ListView(
            padding: const EdgeInsets.all(DoableMetrics.space5),
            children: [
              Notice(
                message: context.knobs.string(
                  label: 'Сообщение',
                  initialValue: 'Отметки дней не загружены.',
                ),
              ),
              const SizedBox(height: DoableMetrics.space6),
              const Notice(
                message:
                    'Не удалось загрузить отметки дней. '
                    'Последние полученные отметки сохранены, '
                    'а выбранная дата и дневные выборы не изменились.',
              ),
            ],
          ),
        ),
      ),
    ),
  ),
];
