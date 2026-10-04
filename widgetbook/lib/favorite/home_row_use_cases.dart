import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

const _title = 'быть здоровым';
const _longTitle =
    'научиться хорошо плавать и перестать бояться глубины в открытой воде';

/// Состояния строки избранного намерения на Главной — [HomeIntentionRow]
/// приложения.
List<WidgetbookUseCase> homeRowUseCases() => [
  WidgetbookUseCase(
    name: 'Готово к действию',
    builder: (context) => HomeIntentionRow(
      row: _row(
        title: _title,
        readiness: IntentionReadiness.ready,
        activeRelationCount: 3,
      ),
      // Строка вне списка Главной перетаскивание не начинает.
      reorder: const HomeRowImmovable(),
      onTap: () {},
    ),
  ),
  WidgetbookUseCase(
    name: 'Не готово к действию',
    builder: (context) => HomeIntentionRow(
      row: _row(title: _title),
      // Строка вне списка Главной перетаскивание не начинает.
      reorder: const HomeRowImmovable(),
      onTap: () {},
    ),
  ),
  WidgetbookUseCase(
    name: 'Длинное название',
    builder: (context) => HomeIntentionRow(
      row: _row(title: _longTitle, activeRelationCount: 12),
      // Строка вне списка Главной перетаскивание не начинает.
      reorder: const HomeRowImmovable(),
      onTap: () {},
    ),
  ),
  WidgetbookUseCase(
    name: 'Ручка доступна',
    builder: (context) => _inReorderableList(
      _row(
        title: _title,
        readiness: IntentionReadiness.ready,
        activeRelationCount: 3,
      ),
    ),
  ),
  WidgetbookUseCase(
    name: 'Ручка недоступна',
    builder: (context) => HomeIntentionRow(
      row: _row(
        title: _title,
        readiness: IntentionReadiness.ready,
        activeRelationCount: 3,
      ),
      // Список Главной сейчас не принимает перестановку.
      reorder: const HomeRowImmovable(),
      onTap: () {},
    ),
  ),
  WidgetbookUseCase(
    name: 'Новое место сохраняется',
    builder: (context) => HomeIntentionRow(
      row: _row(
        title: _title,
        readiness: IntentionReadiness.ready,
        activeRelationCount: 3,
      ),
      reorder: const HomeRowSaving(),
      onTap: () {},
    ),
  ),
];

/// Строка [row] в переставляемом списке, как на Главной: только там ручка
/// начинает перетаскивание, а строка получает системные действия
/// перемещения.
Widget _inReorderableList(FavoriteIntentionRow row) => CustomScrollView(
  shrinkWrap: true,
  slivers: [
    SliverReorderableList(
      itemCount: 1,
      itemBuilder: (context, index) => HomeIntentionRow(
        key: ValueKey(row.id),
        row: row,
        reorder: HomeRowMovable(index),
        onTap: () {},
      ),
      // Единственную строку переставить некуда.
      onReorderItem: (from, to) {},
    ),
  ],
);

FavoriteIntentionRow _row({
  required String title,
  IntentionReadiness readiness = IntentionReadiness.notReady,
  int activeRelationCount = 0,
}) {
  const serialized = '018f0000-0000-7000-8000-000000000001';
  return switch (IntentionId.decode(serialized)) {
    IntentionIdDecodingSuccess(:final id) => FavoriteIntentionRow(
      id: id,
      title: title,
      readiness: readiness,
      activeRelationCount: activeRelationCount,
    ),
    _ => throw StateError(
      'Идентификатор образца намерения недействителен: $serialized',
    ),
  };
}
