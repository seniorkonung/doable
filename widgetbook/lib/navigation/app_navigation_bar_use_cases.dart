import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Состояния панели основной навигации — [AppNavigationBar] приложения:
/// по одному на каждый выбранный пункт.
List<WidgetbookUseCase> appNavigationBarUseCases() => [
  for (final destination in AppDestination.values)
    WidgetbookUseCase(
      name: _useCaseName(destination),
      builder: (context) => Align(
        alignment: Alignment.bottomCenter,
        child: AppNavigationBar(selected: destination, onSelected: (_) {}),
      ),
    ),
];

/// Название примера — понятие каталога, а не системная строка приложения,
/// поэтому от локали примера оно не зависит.
String _useCaseName(AppDestination destination) => switch (destination) {
  AppDestination.home => 'Выбрана Главная',
  AppDestination.dailyChoices => 'Выбраны Дневные выборы',
  AppDestination.intentionGraph => 'Выбран Граф намерений',
};
