import 'package:doable/src/tag/domain/tag_position.dart';

/// Место тега из канонического ключа; неканонический ключ — ошибка проверки.
TagPosition tagPosition(String key) => switch (TagPosition.decode(key)) {
  TagPositionDecodingSuccess(:final position) => position,
  NonCanonicalTagPositionDecoding() => throw ArgumentError.value(key, 'key'),
};

/// Канонический ключ места, который возрастает вместе с [index]: различные
/// номера дают различные места.
String tagPositionKey(int index) {
  RangeError.checkValueInInterval(index, 0, _keyCount - 1, 'index');
  final digits = List.filled(_keyDigits, _alphabet[0]);
  var rest = index;
  for (var at = _keyDigits - 1; at >= 0; at--) {
    digits[at] = _alphabet[rest % _alphabet.length];
    rest ~/= _alphabet.length;
  }
  return 'c${digits.join()}';
}

/// Место тега с ключом [tagPositionKey].
TagPosition tagPositionAt(int index) => tagPosition(tagPositionKey(index));

const _alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// Префикс `c` задаёт целую часть из трёх цифр.
const _keyDigits = 3;
const _keyCount = 62 * 62 * 62;
