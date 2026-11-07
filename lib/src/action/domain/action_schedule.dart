/// Запланированное время действия внутри его даты: целый час или весь день.
/// Минут, длительности и часового пояса нет.
sealed class ActionSchedule {
  const ActionSchedule();
}

final class ActionAllDay extends ActionSchedule {
  const ActionAllDay();

  @override
  bool operator ==(Object other) => other is ActionAllDay;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ActionAtHour extends ActionSchedule {
  /// Принимает час 0–23; иначе выбрасывает [RangeError].
  factory ActionAtHour(int hour) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    return ActionAtHour._(hour);
  }

  const ActionAtHour._(this.hour);

  final int hour;

  @override
  bool operator ==(Object other) => other is ActionAtHour && other.hour == hour;

  @override
  int get hashCode => hour.hashCode;
}
