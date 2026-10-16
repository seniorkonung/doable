/// Планирование внутри календарной даты без длительности и часового пояса.
sealed class DailyChoiceSchedule {
  const DailyChoiceSchedule();
}

final class DailyChoiceAllDay extends DailyChoiceSchedule {
  const DailyChoiceAllDay();

  @override
  bool operator ==(Object other) => other is DailyChoiceAllDay;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class DailyChoiceTime extends DailyChoiceSchedule {
  /// Принимает часы 0–23 и минуты 0–59; иначе выбрасывает [RangeError].
  factory DailyChoiceTime({required int hour, required int minute}) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
    return DailyChoiceTime._(hour, minute);
  }

  const DailyChoiceTime._(this.hour, this.minute);

  final int hour;
  final int minute;

  int get minuteOfDay => hour * 60 + minute;

  @override
  bool operator ==(Object other) =>
      other is DailyChoiceTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}
