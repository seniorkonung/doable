import 'package:doable/src/tag/domain/tag_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('место тега', () {
    test('принимает канонические ключи без изменения', () {
      for (final key in [
        'a0',
        'Zz',
        'b00',
        'zzzzzzzzzzzzzzzzzzzzzzzzzzz',
        'a0V',
        'a0001',
        'Yzzz',
        'A${'0' * 26}1',
        'a0${'z' * 300}',
      ]) {
        expect(_decode(key).value, key, reason: key);
      }
    });

    test('отклоняет неканонические ключи, не исправляя их', () {
      for (final key in [
        '',
        'a0 ',
        ' a0',
        'a-',
        'a0_1',
        'а0',
        'a0é',
        '0',
        '00',
        'a',
        'Z',
        'b0',
        'Y0',
        'A${'0' * 25}',
        'a00',
        'a0V0',
        'Zz10',
        'A${'0' * 26}',
      ]) {
        expect(
          TagPosition.decode(key),
          isA<NonCanonicalTagPositionDecoding>(),
          reason: key,
        );
      }
    });

    test('ставит каждое следующее место перед текущим первым, '
        'меняя префикс длины целой части', () {
      var first = TagPosition.first(null);
      final chain = [first.value];

      for (var step = 0; step < 70; step++) {
        final next = TagPosition.first(first);
        expect(_decode(next.value).value, next.value);
        expect(next.value.compareTo(first.value), lessThan(0));
        chain.add(next.value);
        first = next;
      }

      expect(_decode(chain.first).value, chain.first);
      expect(chain.sublist(61, 64), ['Z1', 'Z0', 'Yzz']);
      expect(TagPosition.first(_decode('b00')).value, 'az');
    });

    test('ставит место перед ключом с дробной частью', () {
      for (final key in ['a0V', 'Zz1', 'b000001']) {
        final before = TagPosition.first(_decode(key));

        expect(_decode(before.value).value, before.value, reason: key);
        expect(before.value.compareTo(key), lessThan(0), reason: key);
      }
    });

    test('ставит место перед ключами у нижней границы целой части', () {
      final smallestInteger = 'A${'0' * 26}';
      for (final key in [
        'A${'0' * 25}1',
        '${smallestInteger}1',
        '${smallestInteger}2',
        '${smallestInteger}0001',
        '${smallestInteger}1z',
        '${smallestInteger}0V',
      ]) {
        final before = TagPosition.first(_decode(key));

        expect(_decode(before.value).value, before.value, reason: key);
        expect(before.value.compareTo(key), lessThan(0), reason: key);
        expect(before.value.compareTo(smallestInteger), greaterThan(0));
      }
    });
  });
}

TagPosition _decode(String key) => switch (TagPosition.decode(key)) {
  TagPositionDecodingSuccess(:final position) => position,
  NonCanonicalTagPositionDecoding() => fail('ключ $key отклонён'),
};
