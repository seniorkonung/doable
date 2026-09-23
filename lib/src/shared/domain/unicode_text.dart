final class InvalidUnicodeTextException implements Exception {
  const InvalidUnicodeTextException();
}

abstract final class UnicodeText {
  static const _highSurrogateStart = 0xd800;
  static const _highSurrogateEnd = 0xdbff;
  static const _lowSurrogateStart = 0xdc00;
  static const _lowSurrogateEnd = 0xdfff;

  static void ensureValidScalarValuesWithoutNul(String value) {
    for (var index = 0; index < value.length; index++) {
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit == 0) {
        throw const InvalidUnicodeTextException();
      }
      if (_isHighSurrogate(codeUnit)) {
        final isFollowedByLowSurrogate =
            index + 1 < value.length &&
            _isLowSurrogate(value.codeUnitAt(index + 1));
        if (!isFollowedByLowSurrogate) {
          throw const InvalidUnicodeTextException();
        }
        index++;
      } else if (_isLowSurrogate(codeUnit)) {
        throw const InvalidUnicodeTextException();
      }
    }
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= _highSurrogateStart && codeUnit <= _highSurrogateEnd;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= _lowSurrogateStart && codeUnit <= _lowSurrogateEnd;
}
