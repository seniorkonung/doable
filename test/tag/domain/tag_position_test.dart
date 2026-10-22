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
      var first = TagPosition.between(null, null);
      final chain = [first.value];

      for (var step = 0; step < 70; step++) {
        final next = TagPosition.between(null, first);
        expect(_decode(next.value).value, next.value);
        expect(next.value.compareTo(first.value), lessThan(0));
        chain.add(next.value);
        first = next;
      }

      expect(_decode(chain.first).value, chain.first);
      expect(chain.sublist(61, 64), ['Z1', 'Z0', 'Yzz']);
      expect(TagPosition.between(null, _decode('b00')).value, 'az');
    });

    test('ставит место перед ключом с дробной частью', () {
      for (final key in ['a0V', 'Zz1', 'b000001']) {
        final before = TagPosition.between(null, _decode(key));

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
        final before = TagPosition.between(null, _decode(key));

        expect(_decode(before.value).value, before.value, reason: key);
        expect(before.value.compareTo(key), lessThan(0), reason: key);
        expect(before.value.compareTo(smallestInteger), greaterThan(0));
      }
    });

    test('ставит место между соседями, удлиняя дробную часть, '
        'когда между ними нет короче', () {
      for (final (before, after, expected) in [
        ('a0', 'a1', 'a0V'),
        ('a0V', 'a0W', 'a0VV'),
        ('a0z', 'a1', 'a0zV'),
        ('a00001', 'a0001', 'a0000W'),
        ('a0', 'a0001', 'a0000V'),
      ]) {
        final between = TagPosition.between(_decode(before), _decode(after));

        expect(between.value, expected, reason: '$before–$after');
        expect(_decode(between.value).value, between.value);
      }
    });

    test('ставит место между соседями с разными префиксами длины '
        'целой части', () {
      for (final (before, after, expected) in [
        ('Zz', 'a0', 'ZzV'),
        ('Zy', 'b05', 'Zz'),
        ('az', 'b00V', 'b00'),
        ('Yzz', 'Z0', 'YzzV'),
      ]) {
        final between = TagPosition.between(_decode(before), _decode(after));

        expect(between.value, expected, reason: '$before–$after');
        expect(_decode(between.value).value, between.value);
      }
    });

    test('ставит место после последнего, а после наибольшей целой части — '
        'в дробной части', () {
      final largestInteger = 'z${'z' * 26}';
      for (final (before, expected) in [
        ('a0', 'a1'),
        ('a0V', 'a1'),
        ('Zz', 'a0'),
        ('az', 'b00'),
        ('Yzz', 'Z0'),
        (largestInteger, '${largestInteger}V'),
        ('${largestInteger}z', '${largestInteger}zV'),
      ]) {
        final after = TagPosition.between(_decode(before), null);

        expect(after.value, expected, reason: before);
        expect(_decode(after.value).value, after.value);
      }
    });

    test('многократная вставка в начало, в конец и в один промежуток даёт '
        'канонические строго упорядоченные места', () {
      final order = [TagPosition.between(null, null)];
      for (var step = 0; step < 40; step++) {
        order.insert(0, TagPosition.between(null, order.first));
        order.add(TagPosition.between(order.last, null));
      }
      // Каждая вставка встаёт сразу после одного и того же соседа и
      // сужает промежуток до него.
      final neighbour = order.length ~/ 2;
      for (var step = 0; step < 200; step++) {
        order.insert(
          neighbour + 1,
          TagPosition.between(order[neighbour], order[neighbour + 1]),
        );
      }

      for (final position in order) {
        expect(_decode(position.value).value, position.value);
      }
      for (var index = 1; index < order.length; index++) {
        expect(
          order[index - 1].value.compareTo(order[index].value),
          lessThan(0),
          reason: '${order[index - 1].value} и ${order[index].value}',
        );
      }
    });
  });
}

TagPosition _decode(String key) => switch (TagPosition.decode(key)) {
  TagPositionDecodingSuccess(:final position) => position,
  NonCanonicalTagPositionDecoding() => fail('ключ $key отклонён'),
};
