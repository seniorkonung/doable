/// Место тега в ручном порядке — дробный ключ base62 по ADR-0039.
///
/// Ключ состоит из целой части с префиксом длины и дробной части без
/// завершающего нуля. Теги упорядочены сравнением ключей по кодовым единицам;
/// для ASCII оно совпадает с сортировкой SQLite `BINARY`.
final class TagPosition {
  const TagPosition._(this.value);

  /// Каноническая строка ключа в сохранённых данных.
  final String value;

  /// Неканонический ключ — повреждение данных, поэтому он отклоняется,
  /// а не исправляется.
  static TagPositionDecoding decode(String serialized) {
    if (serialized.isEmpty) return const NonCanonicalTagPositionDecoding();
    final integerLength = _integerLength(serialized.codeUnitAt(0));
    if (integerLength == null || serialized.length < integerLength) {
      return const NonCanonicalTagPositionDecoding();
    }
    for (var index = 1; index < serialized.length; index++) {
      if (!_digits.contains(serialized[index])) {
        return const NonCanonicalTagPositionDecoding();
      }
    }
    final hasFraction = serialized.length > integerLength;
    if (hasFraction && serialized.endsWith(_zero)) {
      return const NonCanonicalTagPositionDecoding();
    }
    // Перед наименьшей целой частью без дробной нельзя поставить другой ключ.
    if (serialized == _smallestInteger) {
      return const NonCanonicalTagPositionDecoding();
    }
    return TagPositionDecodingSuccess(TagPosition._(serialized));
  }

  /// Место строго между [before] и [after], где [before] меньше [after].
  ///
  /// Без [before] место встаёт перед [after], без [after] — после [before],
  /// без обеих сторон это начальное место пустого каталога.
  static TagPosition between(TagPosition? before, TagPosition? after) {
    if (before != null &&
        after != null &&
        before.value.compareTo(after.value) >= 0) {
      throw ArgumentError('Место ${before.value} не меньше ${after.value}');
    }
    return TagPosition._(_keyBetween(before?.value, after?.value));
  }

  @override
  bool operator ==(Object other) =>
      other is TagPosition && other.value == value;

  @override
  int get hashCode => value.hashCode;

  static const _digits =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static const _zero = '0';
  static const _maxDigit = 'z';
  static const _midDigit = 'V';
  static const _initial = 'a0';
  static final _smallestInteger = 'A${_zero * 26}';

  /// Длина целой части вместе с префиксом: `a`–`z` дают от одной до 26 цифр
  /// неотрицательной части, `Z`–`A` — от одной до 26 цифр отрицательной.
  static int? _integerLength(int head) {
    if (head >= _lowerA && head <= _lowerZ) return head - _lowerA + 2;
    if (head >= _upperA && head <= _upperZ) return _upperZ - head + 2;
    return null;
  }

  static String _keyBetween(String? before, String? after) {
    if (before == null) {
      if (after == null) return _initial;
      final (integer, fraction) = _split(after);
      // Каноническая форма исключает наименьшую целую часть без дробной.
      if (integer == _smallestInteger) {
        return integer + _midpoint('', fraction);
      }
      if (fraction.isNotEmpty) return integer;
      final decremented = _decrementInteger(integer);
      if (decremented == _smallestInteger) return decremented + _midDigit;
      return decremented;
    }

    final (integer, fraction) = _split(before);
    if (after != null) {
      final (afterInteger, afterFraction) = _split(after);
      if (integer == afterInteger) {
        return integer + _midpoint(fraction, afterFraction);
      }
    }
    // Следующая целая часть подходит, если она меньше [after]; после
    // наибольшей целой части место есть только в дробной.
    final incremented = _incrementInteger(integer);
    if (incremented != null &&
        (after == null || incremented.compareTo(after) < 0)) {
      return incremented;
    }
    return integer + _midpoint(fraction, null);
  }

  /// Целая часть с префиксом и дробная часть канонического [key].
  static (String, String) _split(String key) {
    final integerLength = _integerLength(key.codeUnitAt(0))!;
    return (key.substring(0, integerLength), key.substring(integerLength));
  }

  /// Дробная часть строго между [lower] и [upper] без завершающего нуля;
  /// `null` в [upper] — без верхней границы. Обе части без завершающего нуля,
  /// [lower] меньше [upper].
  static String _midpoint(String lower, String? upper) {
    if (upper != null) {
      // [lower] дополняется нулями: завершающие нули не меняют дробь.
      var common = 0;
      while ((common < lower.length ? lower[common] : _zero) == upper[common]) {
        common++;
      }
      if (common > 0) {
        return upper.substring(0, common) +
            _midpoint(
              common < lower.length ? lower.substring(common) : '',
              upper.substring(common),
            );
      }
    }

    final lowerDigit = lower.isEmpty ? 0 : _digits.indexOf(lower[0]);
    final upperDigit = upper == null
        ? _digits.length
        : _digits.indexOf(upper[0]);
    if (upperDigit - lowerDigit > 1) {
      return _digits[(lowerDigit + upperDigit + 1) ~/ 2];
    }
    if (upper != null && upper.length > 1) return upper[0];
    return _digits[lowerDigit] +
        _midpoint(lower.isEmpty ? '' : lower.substring(1), null);
  }

  /// Следующая целая часть; `null` — [integer] наибольшая.
  static String? _incrementInteger(String integer) {
    final head = integer.codeUnitAt(0);
    final digits = integer.substring(1).split('');
    for (var index = digits.length - 1; index >= 0; index--) {
      final digit = _digits.indexOf(digits[index]);
      if (digit < _digits.length - 1) {
        digits[index] = _digits[digit + 1];
        return String.fromCharCode(head) + digits.join();
      }
      digits[index] = _zero;
    }

    // Все цифры были наибольшими: переход к следующему префиксу длины.
    if (head == _upperZ) return 'a$_zero';
    if (head == _lowerZ) return null;
    final nextHead = head + 1;
    if (nextHead > _lowerA) {
      digits.add(_zero);
    } else {
      digits.removeLast();
    }
    return String.fromCharCode(nextHead) + digits.join();
  }

  /// Предыдущая целая часть; [integer] не равна наименьшей.
  static String _decrementInteger(String integer) {
    final head = integer.codeUnitAt(0);
    final digits = integer.substring(1).split('');
    for (var index = digits.length - 1; index >= 0; index--) {
      final digit = _digits.indexOf(digits[index]);
      if (digit > 0) {
        digits[index] = _digits[digit - 1];
        return String.fromCharCode(head) + digits.join();
      }
      digits[index] = _maxDigit;
    }

    // Все цифры были нулями: переход к предыдущему префиксу длины.
    if (head == _lowerA) return 'Z$_maxDigit';
    final previousHead = head - 1;
    if (previousHead >= _lowerA) {
      digits.removeLast();
    } else {
      digits.add(_maxDigit);
    }
    return String.fromCharCode(previousHead) + digits.join();
  }

  static final _lowerA = 'a'.codeUnitAt(0);
  static final _lowerZ = 'z'.codeUnitAt(0);
  static final _upperA = 'A'.codeUnitAt(0);
  static final _upperZ = 'Z'.codeUnitAt(0);
}

sealed class TagPositionDecoding {
  const TagPositionDecoding();
}

final class TagPositionDecodingSuccess extends TagPositionDecoding {
  const TagPositionDecodingSuccess(this.position);

  final TagPosition position;
}

final class NonCanonicalTagPositionDecoding extends TagPositionDecoding {
  const NonCanonicalTagPositionDecoding();
}
