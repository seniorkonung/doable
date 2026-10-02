import 'dart:math' as math;

import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/app_shell_tab_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _barHeights = <double>[56, 64, 80, 96];
const _safeBottoms = <double>[0, 34];

void main() {
  for (final barHeight in _barHeights) {
    for (final safeBottom in _safeBottoms) {
      final covered = barHeight + safeBottom;
      // Клавиатура отсутствует, ниже, равна и выше суммы высоты панели и
      // нижнего безопасного отступа.
      final keyboards = <String, double>{
        'без клавиатуры': 0,
        'клавиатура ниже панели': covered - 20,
        'клавиатура равна панели': covered,
        'клавиатура выше панели': covered + 236,
      };
      for (final MapEntry(key: name, value: keyboard) in keyboards.entries) {
        testWidgets('панель $barHeight, безопасный отступ $safeBottom, '
            '$name: вставка клавиатуры уменьшается на высоту панели и отступ, '
            'нижний отступ обнуляется', (tester) async {
          final probe = _Probe();
          await tester.pumpWidget(
            _host(
              data: _data(keyboard: keyboard, safeBottom: safeBottom),
              barHeight: barHeight,
              probe: probe,
            ),
          );

          expect(
            probe.data.viewInsets.bottom,
            math.max<double>(0, keyboard - barHeight - safeBottom),
          );
          expect(probe.data.padding.bottom, 0);
          expect(probe.data.viewPadding.bottom, 0);
        });
      }
    }
  }

  testWidgets('клавиатура, закрывшая безопасный отступ, уменьшается только на '
      'высоту панели', (tester) async {
    // Платформа обнуляет нижний отступ, когда клавиатура выше него, а
    // физический отступ экрана оставляет прежним.
    final probe = _Probe();
    await tester.pumpWidget(
      _host(
        data: const MediaQueryData(
          size: Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: 300),
          viewPadding: EdgeInsets.only(bottom: 34),
        ),
        barHeight: 64,
        probe: probe,
      ),
    );

    expect(probe.data.viewInsets.bottom, 236);
    expect(probe.data.padding.bottom, 0);
    expect(probe.data.viewPadding.bottom, 34);
  });

  testWidgets('остальные данные MediaQuery передаются без изменения', (
    tester,
  ) async {
    const source = MediaQueryData(
      size: Size(400, 800),
      devicePixelRatio: 3,
      textScaler: TextScaler.linear(2.5),
      platformBrightness: Brightness.dark,
      padding: EdgeInsets.fromLTRB(11, 47, 13, 34),
      viewPadding: EdgeInsets.fromLTRB(11, 47, 13, 34),
      viewInsets: EdgeInsets.fromLTRB(3, 5, 7, 300),
      systemGestureInsets: EdgeInsets.fromLTRB(20, 0, 20, 34),
      alwaysUse24HourFormat: true,
      accessibleNavigation: true,
      disableAnimations: true,
      boldText: true,
    );
    final probe = _Probe();
    await tester.pumpWidget(_host(data: source, barHeight: 64, probe: probe));

    expect(
      probe.data,
      source.copyWith(
        padding: const EdgeInsets.fromLTRB(11, 47, 13, 0),
        viewPadding: const EdgeInsets.fromLTRB(11, 47, 13, 0),
        viewInsets: const EdgeInsets.fromLTRB(3, 5, 7, 202),
      ),
    );
  });

  testWidgets('изменение вставки клавиатуры и безопасного отступа меняет '
      'заменённые данные без пересоздания содержимого', (tester) async {
    final probe = _Probe();
    Future<void> pump(MediaQueryData data) => tester.pumpWidget(
      _host(data: data, barHeight: AppNavigationBar.height, probe: probe),
    );

    await pump(_data(keyboard: 0, safeBottom: 34));
    expect(probe.data.viewInsets.bottom, 0);
    expect(probe.data.padding.bottom, 0);

    await pump(_data(keyboard: 400, safeBottom: 34));
    expect(probe.data.viewInsets.bottom, 400 - AppNavigationBar.height - 34);

    await pump(_data(keyboard: 400, safeBottom: 0));
    expect(probe.data.viewInsets.bottom, 400 - AppNavigationBar.height);

    await pump(_data(keyboard: 0, safeBottom: 0));
    expect(probe.data.viewInsets.bottom, 0);
    expect(probe.data.padding.bottom, 0);

    expect(probe.created, 1);
    expect(probe.disposed, 0);
  });

  testWidgets('изменение высоты панели меняет заменённые данные без '
      'пересоздания содержимого', (tester) async {
    final probe = _Probe();
    final data = _data(keyboard: 300, safeBottom: 0);

    await tester.pumpWidget(_host(data: data, barHeight: 56, probe: probe));
    expect(probe.data.viewInsets.bottom, 244);

    await tester.pumpWidget(_host(data: data, barHeight: 96, probe: probe));
    expect(probe.data.viewInsets.bottom, 204);

    expect(probe.created, 1);
  });

  testWidgets('тело Scaffold внутри замены заканчивается на верхней границе '
      'большего из клавиатуры и панели', (tester) async {
    const screen = Size(400, 800);
    const safeBottom = 34.0;
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final barHeight in _barHeights) {
      for (final keyboard in <double>[0, 50, barHeight + safeBottom, 300]) {
        await tester.pumpWidget(
          MediaQuery(
            data: _data(keyboard: keyboard, safeBottom: safeBottom),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Expanded(
                    child: AppShellTabInsets(
                      barHeight: barHeight,
                      child: const Scaffold(
                        body: SizedBox.expand(key: Key('body')),
                      ),
                    ),
                  ),
                  SizedBox(height: barHeight + safeBottom),
                ],
              ),
            ),
          ),
        );

        expect(
          tester.getRect(find.byKey(const Key('body'))).bottom,
          screen.height - math.max<double>(keyboard, barHeight + safeBottom),
          reason: 'панель $barHeight, клавиатура $keyboard',
        );
      }
    }
  });
}

/// Данные экрана без клавиатуры над безопасным отступом: нижний отступ равен
/// физическому отступу экрана.
MediaQueryData _data({required double keyboard, required double safeBottom}) {
  return MediaQueryData(
    size: const Size(400, 800),
    padding: EdgeInsets.only(bottom: safeBottom),
    viewPadding: EdgeInsets.only(bottom: safeBottom),
    viewInsets: EdgeInsets.only(bottom: keyboard),
  );
}

Widget _host({
  required MediaQueryData data,
  required double barHeight,
  required _Probe probe,
}) {
  return MediaQuery(
    data: data,
    child: AppShellTabInsets(barHeight: barHeight, child: _ProbeWidget(probe)),
  );
}

/// Наблюдения содержимого: полученные данные `MediaQuery` и число созданий
/// и удалений его состояния.
final class _Probe {
  late MediaQueryData data;
  int created = 0;
  int disposed = 0;
}

final class _ProbeWidget extends StatefulWidget {
  const _ProbeWidget(this.probe);

  final _Probe probe;

  @override
  State<_ProbeWidget> createState() => _ProbeWidgetState();
}

final class _ProbeWidgetState extends State<_ProbeWidget> {
  @override
  void initState() {
    super.initState();
    widget.probe.created += 1;
  }

  @override
  void dispose() {
    widget.probe.disposed += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.probe.data = MediaQuery.of(context);
    return const SizedBox.shrink();
  }
}
