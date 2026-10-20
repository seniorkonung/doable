import 'package:flutter_test/flutter_test.dart';

/// Дожидается появления элемента [finder].
Future<void> until(WidgetTester tester, Finder finder) =>
    waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Даёт фоновой работе завершиться: результат, который она показала бы,
/// появился бы за эти шаги.
Future<void> settle(WidgetTester tester) async {
  for (var step = 0; step < 10; step++) {
    await advance(tester);
  }
}

/// Продвигает время, пока не выполнится [done]. Шагов хватает, чтобы
/// показанное сообщение общей поверхности закрылось по таймеру.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var step = 0; step < 100 && !done(); step++) {
    await advance(tester);
  }
  expect(done(), isTrue);
}

/// Один шаг времени: реальное ожидание, в котором идут операции хранилища,
/// копирование документа и изоляты записи состояния и снимка замены, и кадр
/// через 100 мс.
Future<void> advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
