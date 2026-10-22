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

  /// Место тега, который становится первым: начальное в пустом каталоге,
  /// иначе строго перед [currentFirst].
  static TagPosition first(TagPosition? currentFirst) {
    if (currentFirst == null) return const TagPosition._(_initial);

    final key = currentFirst.value;
    final integer = key.substring(0, _integerLength(key.codeUnitAt(0))!);
    final fraction = key.substring(integer.length);
    // Каноническая форма исключает наименьшую целую часть без дробной.
    if (integer == _smallestInteger) {
      return TagPosition._(integer + _fractionBelow(fraction));
    }
    if (fraction.isNotEmpty) return TagPosition._(integer);

    final decremented = _decrementInteger(integer);
    if (decremented == _smallestInteger) {
      return TagPosition._(decremented + _midDigit);
    }
    return TagPosition._(decremented);
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

  /// Дробная часть строго меньше непустой [fraction] без завершающего нуля.
  static String _fractionBelow(String fraction) {
    var zeros = 0;
    while (fraction[zeros] == _zero) {
      zeros++;
    }
    final prefix = fraction.substring(0, zeros);
    final digit = _digits.indexOf(fraction[zeros]);
    if (digit > 1) return prefix + _digits[(digit + 1) ~/ 2];
    if (fraction.length > zeros + 1) return prefix + fraction[zeros];
    return '$prefix$_zero$_midDigit';
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
