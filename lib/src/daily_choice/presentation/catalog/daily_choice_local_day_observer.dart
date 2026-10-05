import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/calendar_date.dart';
import 'daily_choice_local_date_provider.dart';

/// Следит за местным сегодня, которое каталог дневных выборов обозначает в
/// календаре.
///
/// Читает часы при создании, при каждом возвращении приложения в активное
/// состояние и в начале следующей местной даты. Держит один таймер до начала
/// следующей даты: каждое чтение заменяет прежний таймер новым, рассчитанным
/// по свежему показанию. Поэтому сутки с переводом часов, дни, пропущенные
/// приостановленным процессом, и смена часового пояса в фоне не сдвигают
/// обозначение.
///
/// О смене сегодняшнего дня сообщает [onTodayChanged]; выбранную дату,
/// просмотр календаря и выдачу каталога наблюдатель не трогает. После
/// [dispose] часы не читаются и вызовов нет.
final class DailyChoiceLocalDayObserver with WidgetsBindingObserver {
  DailyChoiceLocalDayObserver({
    required this.readLocalDay,
    required this.onTodayChanged,
  }) {
    _today = _readAndSchedule();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Часы, которые наблюдатель читает.
  final DailyChoiceLocalDateSource readLocalDay;

  /// Вызывается, когда очередное чтение часов дало другую местную дату.
  final VoidCallback onTodayChanged;

  late CalendarDate _today;
  Timer? _nextDate;

  /// Местная дата последнего чтения часов.
  CalendarDate get today => _today;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nextDate?.cancel();
    _nextDate = null;
  }

  void _refresh() {
    final previous = _today;
    _today = _readAndSchedule();
    if (_today != previous) onTodayChanged();
  }

  CalendarDate _readAndSchedule() {
    final localDay = readLocalDay();
    _nextDate?.cancel();
    _nextDate = Timer(localDay.untilNextDate, _refresh);
    return localDay.date;
  }
}
