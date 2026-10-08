import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Состояния панели основной навигации — [AppNavigationBar] приложения:
/// по одному на каждый выбранный пункт в раскладке обычной страницы.
/// Масштаб текста меняется дополнением Widgetbook вплоть до 2.5.
List<WidgetbookUseCase> appNavigationBarUseCases() => [
  for (final destination in AppDestination.values)
    WidgetbookUseCase(
      name: _useCaseName(destination),
      // Повторяет раскладку OrdinaryPageScaffold без зависимости примера
      // компонента от маршрутизатора и хранилища приложения.
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(destination.title(AppLocalizations.of(context))),
        ),
        body: SafeArea(
          child: Center(child: Icon(destination.selectedIcon, size: 64)),
        ),
        bottomNavigationBar: AppNavigationBar(
          selected: destination,
          quickCreationMode: QuickCreationMode.intention,
          onQuickCreate: () {},
          onChangeQuickCreationMode: () {},
          onSelected: (_) {},
        ),
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
