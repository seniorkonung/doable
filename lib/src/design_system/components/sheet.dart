import 'dart:math' as math;
import 'dart:ui' show clampDouble, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';
import 'button.dart';

/// Возможность построить лист по содержимому [Sheet.new].
///
/// Её даёт построителю только [showDoableSheet]: она несёт маршрут этой
/// функции, анимацию которого лист ведёт пальцем.
final class ContentSheetCapability {
  const ContentSheetCapability._(this._route);

  final _DoableSheetRoute<Object?> _route;
}

/// Возможность построить раскрываемый лист [Sheet.expandable].
///
/// Её даёт построителю только [showDoableExpandableSheet]: маршрут этой
/// функции не перетаскивает лист, а жест шапки обрабатывает сам лист.
final class ExpandableSheetCapability {
  const ExpandableSheetCapability._();
}

/// Показывает лист высотой по содержимому над корневым навигатором,
/// перекрывая всю страницу и панель.
///
/// [builder] строит [Sheet] или композицию на его основе с переданной
/// возможностью. Потребитель закрывает лист через Navigator.pop с результатом
/// типа [T]; закрытие без выбора даёт null. Лист перетаскивает сам [Sheet],
/// а затемнение, системное «назад», фокус и семантика маршрута принадлежат
/// модальной нижней панели Material:
/// https://api.flutter.dev/flutter/material/ModalBottomSheetRoute-class.html
///
/// С [hostsMessages] лист содержит собственный прозрачный [Scaffold], и
/// сообщения общего [ScaffoldMessenger] появляются над его нижней частью, а не
/// на странице под листом. Признак нужен листу, который остаётся открытым до
/// результата начатой в нём операции.
Future<T?> showDoableSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ContentSheetCapability sheet)
  builder,
  bool hostsMessages = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  // Без явного нуля маршрут лишь укоротил бы анимацию в 20 раз:
  // https://api.flutter.dev/flutter/animation/AnimationBehavior.html
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : _sheetDuration;
  late final _DoableSheetRoute<T> route;
  route = _DoableSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    barrierColor: _colorsOf(Theme.of(context)).scrim,
    // Готовый AnimationStyle.noAnimation не подходит: без его кривых
    // Material ставит лист своей кривой, и лист уходит от пальца.
    animationStyle: AnimationStyle(
      curve: _sheetCurve,
      reverseCurve: _sheetCurve,
      duration: duration,
      reverseDuration: duration,
    ),
    builder: (context) => _ExtentProbe(
      onLayout: (height) => route._extent = height,
      child: _SheetFrame(
        hostsMessages: hostsMessages,
        child: builder(context, ContentSheetCapability._(route)),
      ),
    ),
  );
  return navigator.push(route);
}

/// Показывает раскрываемый лист [Sheet.expandable] над корневым навигатором,
/// перекрывая всю страницу и панель.
///
/// Результат и [hostsMessages] — как у [showDoableSheet]. Перетаскивание
/// листа Material здесь выключено: половинный лист жестом шапки закрывает сам
/// [Sheet] через Navigator.pop, а барьер, системное «назад» и семантика
/// маршрута по-прежнему принадлежат Material.
Future<T?> showDoableExpandableSheet<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    ExpandableSheetCapability sheet,
  )
  builder,
  bool hostsMessages = false,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  requestFocus: true,
  barrierColor: _colorsOf(Theme.of(context)).scrim,
  backgroundColor: Colors.transparent,
  elevation: 0,
  shape: const RoundedRectangleBorder(),
  clipBehavior: Clip.none,
  // Лист занимает всю доступную ширину, без ограничения Material 3 в 640 dp.
  constraints: const BoxConstraints(maxWidth: double.infinity),
  showDragHandle: false,
  isDismissible: true,
  enableDrag: false,
  builder: (context) => _SheetFrame(
    hostsMessages: hostsMessages,
    child: builder(context, const ExpandableSheetCapability._()),
  ),
);

/// Длительность движения листа, которое не ведёт палец.
const _sheetDuration = Duration(milliseconds: 180);

/// Кривая маршрута листа в обе стороны.
///
/// Лист ставит значение маршрута через [_inverseSheetCurve], поэтому кривая
/// одна и для открытия, и для закрытия.
const _sheetCurve = Curves.easeOut;

/// Значение маршрута, при котором [_sheetCurve] даёт положение [position].
///
/// Делением пополам находит параметр кривой Безье, при котором её ордината
/// равна [position], и возвращает абсциссу при нём:
/// https://api.flutter.dev/flutter/animation/Cubic-class.html
double _inverseSheetCurve(double position) {
  // Концы кривой ставятся точно, чтобы лист у края пути стоял ровно в
  // компактном размере или в закрытом.
  if (position <= 0 || position >= 1) return clampDouble(position, 0, 1);
  const curve = _sheetCurve;
  double evaluate(double first, double second, double m) =>
      3 * first * (1 - m) * (1 - m) * m +
      3 * second * (1 - m) * m * m +
      m * m * m;
  var low = 0.0;
  var high = 1.0;
  for (var step = 0; step < 32; step++) {
    final middle = (low + high) / 2;
    if (evaluate(curve.b, curve.d, middle) < position) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return evaluate(curve.a, curve.c, (low + high) / 2);
}

/// Маршрут листа по содержимому: модальная нижняя панель Material без её
/// перетаскивания, анимацию которой ведёт пальцем [_SheetMotion].
final class _DoableSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _DoableSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required Color barrierColor,
    required AnimationStyle animationStyle,
  }) : super(
         modalBarrierColor: barrierColor,
         sheetAnimationStyle: animationStyle,
         useSafeArea: true,
         isScrollControlled: true,
         requestFocus: true,
         backgroundColor: Colors.transparent,
         elevation: 0,
         shape: const RoundedRectangleBorder(),
         clipBehavior: Clip.none,
         // Лист занимает всю доступную ширину, без ограничения Material 3 в
         // 640 dp.
         constraints: const BoxConstraints(maxWidth: double.infinity),
         showDragHandle: false,
         isDismissible: true,
         enableDrag: false,
       );

  /// Высота, на которую маршрут уводит лист при закрытии, при последней
  /// раскладке: лист вместе с отступом клавиатуры под ним.
  double _extent = 0;

  /// Значение анимации маршрута: 0 — лист закрыт, 1 — в компактном размере.
  AnimationController get _animation => controller!;
}

/// Отступ листа от открытой клавиатуры и, с [hostsMessages], отметка листа
/// для собственного [Scaffold].
final class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.hostsMessages, required this.child});

  final bool hostsMessages;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    // SafeArea учитывает системные панели, но не открытую клавиатуру.
    // https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: hostsMessages ? _MessagesHost(child: child) : child,
  );
}

/// Ведёт лист пальцем между закрытым и компактным размером и после
/// отпускания доводит его до компактного размера или закрывает.
///
/// Положение листа — доля видимой высоты, значение маршрута после
/// [_sheetCurve]. Пороги скорости и положения — те же, что у перетаскивания
/// модальной нижней панели Material.
final class _SheetMotion extends StatefulWidget {
  const _SheetMotion({required this.route, required this.child});

  final _DoableSheetRoute<Object?> route;
  final Widget child;

  @override
  State<_SheetMotion> createState() => _SheetMotionState();
}

final class _SheetMotionState extends State<_SheetMotion> {
  static const _flingVelocity = 700.0;
  static const _closePosition = 0.5;

  /// Касание, с которого начат текущий жест, и положение листа при нём.
  late ({double y, double position}) _drag;
  var _isPointerCanceled = false;

  _DoableSheetRoute<Object?> get _route => widget.route;

  double get _position => _sheetCurve.transform(_route._animation.value);

  void _startDrag(DragStartDetails details) {
    _drag = (y: details.globalPosition.dy, position: _position);
  }

  void _updateDrag(DragUpdateDetails details) {
    // Положение вычисляется от начала жеста, а не накапливается из сдвигов,
    // поэтому ошибка обратной функции кривой не накапливается.
    final distance = details.globalPosition.dy - _drag.y;
    final position = clampDouble(
      _drag.position - distance / _route._extent,
      0,
      1,
    );
    _route._animation.value = _inverseSheetCurve(position);
  }

  void _endDrag(DragEndDetails details) {
    // Закрыв или перекрыв лист во время жеста, Navigator отменяет касания, и
    // жест завершается здесь. Доводка тогда остановила бы закрытие, а
    // Navigator.pop закрыл бы маршрут под листом.
    if (!_route.isCurrent) return;
    // Принятый жест Flutter завершает через onEnd даже при PointerCancelEvent:
    // https://api.flutter.dev/flutter/gestures/DragGestureRecognizer/didStopTrackingLastPointer.html
    if (_isPointerCanceled) {
      _route._animation.forward();
      return;
    }
    final velocity = details.velocity.pixelsPerSecond.dy;
    final closes = switch (velocity) {
      > _flingVelocity => true,
      < -_flingVelocity => false,
      _ => _position < _closePosition,
    };
    if (closes) {
      Navigator.pop(context);
    } else {
      _route._animation.forward();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _isPointerCanceled = false,
    onPointerCancel: (_) => _isPointerCanceled = true,
    child: GestureDetector(
      // Лист под пальцем стоит той точкой, которой его коснулись:
      // https://api.flutter.dev/flutter/gestures/DragStartBehavior.html
      dragStartBehavior: DragStartBehavior.down,
      // Как у модальной нижней панели Material, перетаскивание не
      // объявляется диктору прокруткой.
      excludeFromSemantics: true,
      onVerticalDragStart: _startDrag,
      onVerticalDragUpdate: _updateDrag,
      onVerticalDragEnd: _endDrag,
      child: widget.child,
    ),
  );
}

/// Отмечает лист, показанный с `hostsMessages`.
final class _MessagesHost extends InheritedWidget {
  const _MessagesHost({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MessagesHost>() != null;

  @override
  bool updateShouldNotify(_MessagesHost oldWidget) => false;
}

/// Действие шапки раскрываемого листа: подпись, доступное название и
/// обработчик нажатия.
typedef SheetAction = ({
  String label,
  String semanticLabel,
  VoidCallback onPressed,
});

/// Лист с ручкой, заголовком, пояснением, телом и нижней частью.
///
/// Вариант листа строится только с возможностью, которую даёт построителю
/// его функция показа: [showDoableSheet] или [showDoableExpandableSheet].
final class Sheet extends StatelessWidget {
  /// Лист высотой по содержимому.
  ///
  /// Лист перетаскивается за шапку, нижнюю часть и тело, которое помещается
  /// целиком, и закрывается жестом вниз; касание затемнения и «назад»
  /// закрывают его средствами Material маршрута [showDoableSheet]. При
  /// нехватке высоты прокручивается только тело: шапка остаётся доступной для
  /// свайпа, а нижняя часть — видна под телом.
  const Sheet(
    ContentSheetCapability this._content, {
    required this.title,
    required this.child,
    this.text,
    this.footer,
    super.key,
  }) : _expansion = null;

  /// Лист половинной высоты, который раскрывается на весь экран.
  ///
  /// Перетаскивание шапки на 48 вверх раскрывает лист, вниз — сворачивает
  /// полный или закрывает половинный через Navigator.pop; нажатие на ручку
  /// переключает размер. Касание затемнения и «назад» закрывают лист
  /// средствами Material маршрута [showDoableExpandableSheet].
  /// [body] — собственный прокручиваемый список тела, который занимает место
  /// между [pinned] и [footer]; его прокрутка не меняет размер листа.
  /// [expandLabel] и [collapseLabel] — доступные названия ручки.
  /// [action] — текстовая кнопка размера sm справа на строке заголовка,
  /// например «Сбросить»; заголовок при ней остаётся по центру.
  const Sheet.expandable(
    ExpandableSheetCapability _, {
    required this.title,
    required String text,
    required Widget pinned,
    required Widget body,
    required Widget footer,
    required String expandLabel,
    required String collapseLabel,
    SheetAction? action,
    super.key,
  }) : text = text,
       child = body,
       footer = footer,
       _content = null,
       _expansion = (
         text: text,
         pinned: pinned,
         footer: footer,
         expandLabel: expandLabel,
         collapseLabel: collapseLabel,
         action: action,
       );

  final String title;

  /// Пояснение под заголовком; без него тело следует сразу за заголовком.
  final String? text;

  /// Тело листа.
  final Widget child;

  /// Основная кнопка листа на всю ширину, закреплённая под телом вне его
  /// прокрутки; без неё лист заканчивается телом.
  final Widget? footer;

  /// Возможность листа по содержимому; у раскрываемого листа её нет.
  final ContentSheetCapability? _content;

  /// Части раскрываемого листа; без них лист — по содержимому.
  final _Expansion? _expansion;

  @override
  Widget build(BuildContext context) {
    if (_expansion case final expansion?) {
      return _ExpandableSheet(title: title, body: child, expansion: expansion);
    }
    final theme = Theme.of(context);
    final colors = _colorsOf(theme);
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(DoableMetrics.radiusXl),
    );

    return _SheetMotion(
      route: _content!._route,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: _shadowsOf(theme).shadowFloat,
        ),
        child: Material(
          color: colors.raised,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: _SheetLayout(
            minimum: const EdgeInsets.fromLTRB(
              DoableMetrics.space3,
              DoableMetrics.space2,
              DoableMetrics.space3,
              0,
            ),
            head: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _Grip(color: colors.grip)),
                const SizedBox(height: 14),
                _TitleBlock(title: title, text: text, action: null),
                const SizedBox(height: DoableMetrics.space3),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
            footer: switch (footer) {
              final footer? => _Footer(child: footer),
              null => null,
            },
          ),
        ),
      ),
    );
  }
}

/// Раскладка частей листа над закреплённой нижней частью [footer] с учётом
/// безопасной области.
final class _SheetLayout extends StatelessWidget {
  const _SheetLayout({
    required this.minimum,
    required this.head,
    required this.footer,
  });

  /// Наименьшие отступы содержимого; нижний не прибавляется к системному.
  final EdgeInsets minimum;

  /// Содержимое над нижней частью; занимает не больше доступной высоты.
  final Widget head;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (_MessagesHost.of(context)) {
      return _MessagesScaffold(minimum: minimum, head: head, footer: footer);
    }
    return SafeArea(
      top: false,
      minimum: minimum,
      // Нижний minimum не прибавлялся бы к системному отступу:
      // https://api.flutter.dev/flutter/widgets/SafeArea/minimum.html
      child: Padding(
        padding: _bottomPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: head),
            ?footer,
          ],
        ),
      ),
    );
  }
}

const _bottomPadding = EdgeInsets.only(bottom: DoableMetrics.space4);

/// Раскладка листа с `hostsMessages`: [footer] стоит в `bottomNavigationBar`
/// собственного [Scaffold], и сообщение появляется над ним.
///
/// Отступы и высота те же, что у листа без [Scaffold]: лист по содержимому
/// следует за [head] и [footer], а клавиатуру учитывает только функция
/// показа листа.
final class _MessagesScaffold extends StatefulWidget {
  const _MessagesScaffold({
    required this.minimum,
    required this.head,
    required this.footer,
  });

  final EdgeInsets minimum;
  final Widget head;
  final Widget? footer;

  @override
  State<_MessagesScaffold> createState() => _MessagesScaffoldState();
}

final class _MessagesScaffoldState extends State<_MessagesScaffold> {
  final _extents = _ScaffoldExtents();

  @override
  Widget build(BuildContext context) {
    final minimum = widget.minimum;
    // Scaffold снимает с тела нижний системный отступ при нижней части, а ей
    // самой без resizeToAvoidBottomInset оставляет его и над клавиатурой:
    // https://api.flutter.dev/flutter/material/Scaffold/resizeToAvoidBottomInset.html
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final footer = widget.footer;
    return _ScaffoldFrame(
      extents: _extents,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: _ExtentProbe(
          onLayout: (height) => _extents.body = height,
          child: SafeArea(
            top: false,
            minimum: minimum,
            child: footer == null
                ? Padding(padding: _bottomPadding, child: widget.head)
                : widget.head,
          ),
        ),
        bottomNavigationBar: footer == null
            ? null
            : _ExtentProbe(
                onLayout: (height) => _extents.footer = height,
                child: SafeArea(
                  top: false,
                  bottom: false,
                  minimum: minimum.copyWith(top: 0, bottom: 0),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: systemBottom + DoableMetrics.space4,
                    ),
                    child: footer,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Высоты тела и нижней части [Scaffold] листа при последней раскладке.
final class _ScaffoldExtents {
  var body = 0.0;
  var footer = 0.0;
}

/// Сообщает высоту, которую занял [child].
final class _ExtentProbe extends SingleChildRenderObjectWidget {
  const _ExtentProbe({required this.onLayout, required super.child});

  final ValueChanged<double> onLayout;

  @override
  _RenderExtentProbe createRenderObject(BuildContext context) =>
      _RenderExtentProbe(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExtentProbe renderObject,
  ) => renderObject.onLayout = onLayout;
}

final class _RenderExtentProbe extends RenderProxyBox {
  _RenderExtentProbe(this.onLayout);

  ValueChanged<double> onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout(size.height);
  }
}

/// Ограничивает [Scaffold] листа высотой его тела и нижней части, когда
/// высота задана только сверху.
///
/// [Scaffold] занимает всю данную ему высоту, поэтому сначала раскладывается
/// в неё, и тело получает содержимое по его высоте; затем — повторно в высоту
/// тела и нижней части. Оба ограничения нестрогие, поэтому изменение
/// содержимого снова доходит до раскладки листа.
final class _ScaffoldFrame extends SingleChildRenderObjectWidget {
  const _ScaffoldFrame({required this.extents, required super.child});

  final _ScaffoldExtents extents;

  @override
  _RenderScaffoldFrame createRenderObject(BuildContext context) =>
      _RenderScaffoldFrame(extents);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScaffoldFrame renderObject,
  ) => renderObject.extents = extents;
}

final class _RenderScaffoldFrame extends RenderProxyBox {
  _RenderScaffoldFrame(this._extents);

  _ScaffoldExtents _extents;

  set extents(_ScaffoldExtents value) {
    if (identical(value, _extents)) {
      return;
    }
    _extents = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Высота листа зависит от раскладки его Scaffold.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    final scaffold = child!;
    scaffold.layout(constraints, parentUsesSize: true);
    if (!constraints.hasTightHeight) {
      final height = constraints.constrainHeight(
        _extents.body + _extents.footer,
      );
      if (height < scaffold.size.height) {
        scaffold.layout(
          constraints.copyWith(maxHeight: height),
          parentUsesSize: true,
        );
      }
    }
    size = scaffold.size;
  }
}

typedef _Expansion = ({
  String text,
  Widget pinned,
  Widget footer,
  String expandLabel,
  String collapseLabel,
  SheetAction? action,
});

final class _ExpandableSheet extends StatefulWidget {
  const _ExpandableSheet({
    required this.title,
    required this.body,
    required this.expansion,
  });

  final String title;
  final Widget body;
  final _Expansion expansion;

  @override
  State<_ExpandableSheet> createState() => _ExpandableSheetState();
}

final class _ExpandableSheetState extends State<_ExpandableSheet>
    with SingleTickerProviderStateMixin {
  static const _halfHeight = 534.0;
  static const _dragThreshold = 48.0;

  /// 0 — половинная высота, 1 — весь экран.
  late final _expansion = AnimationController(
    vsync: this,
    duration: _sheetDuration,
  );
  var _isFull = false;
  double? _dragStartY;
  var _dragY = 0.0;
  var _isPointerCanceled = false;

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  void _resize({required bool full}) {
    setState(() => _isFull = full);
    // Без явного нуля контроллер лишь укорачивает анимацию в 20 раз:
    // https://api.flutter.dev/flutter/animation/AnimationBehavior.html
    _expansion.animateTo(
      full ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : null,
      curve: Curves.easeOut,
    );
  }

  void _startDrag(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragY = details.globalPosition.dy;
  }

  void _updateDrag(DragUpdateDetails details) {
    _dragY = details.globalPosition.dy;
  }

  void _endDrag(DragEndDetails _) {
    final startY = _dragStartY;
    _dragStartY = null;
    // Принятый жест Flutter завершает через onEnd даже при PointerCancelEvent:
    // https://api.flutter.dev/flutter/gestures/DragGestureRecognizer/didStopTrackingLastPointer.html
    if (startY == null || _isPointerCanceled) return;
    final distance = _dragY - startY;
    if (distance.abs() < _dragThreshold) return;
    if (distance < 0) {
      if (!_isFull) _resize(full: true);
    } else if (_isFull) {
      _resize(full: false);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colorsOf(theme);
    final shadows = _shadowsOf(theme);
    final expansion = widget.expansion;

    final handle = Semantics(
      container: true,
      button: true,
      expanded: _isFull,
      label: _isFull ? expansion.collapseLabel : expansion.expandLabel,
      child: InkWell(
        onTap: () => _resize(full: !_isFull),
        borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        child: SizedBox(
          width: 88,
          height: DoableMetrics.tapMin,
          child: _isFull
              ? Center(
                  child: DoableIcon(
                    DoableIconData.chevronDown,
                    size: 28,
                    color: colors.grip,
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: DoableMetrics.space2),
                    child: _Grip(color: colors.grip),
                  ),
                ),
        ),
      ),
    );
    final titleBlock = _TitleBlock(
      title: widget.title,
      text: expansion.text,
      action: switch (expansion.action) {
        final action? => Button.text(
          label: action.label,
          semanticLabel: action.semanticLabel,
          onPressed: action.onPressed,
        ),
        null => null,
      },
    );
    // Ручка половинного листа стоит над началом заголовка, чтобы область
    // нажатия была не меньше 44 при прежнем положении ручки и заголовка.
    final header = _isFull
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: DoableMetrics.space2),
              Center(child: handle),
              const SizedBox(height: DoableMetrics.space1),
              titleBlock,
            ],
          )
        : Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 26),
                child: titleBlock,
              ),
              Align(alignment: Alignment.topCenter, child: handle),
            ],
          );

    final content = _SheetLayout(
      minimum: const EdgeInsets.symmetric(horizontal: DoableMetrics.space3),
      head: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Listener(
            onPointerDown: (_) => _isPointerCanceled = false,
            onPointerCancel: (_) => _isPointerCanceled = true,
            child: GestureDetector(
              // Вся шапка — область свайпа, включая пустые места у краёв.
              behavior: HitTestBehavior.opaque,
              // Сдвиг считается от касания, а не от преодоления допуска:
              // https://api.flutter.dev/flutter/gestures/DragStartBehavior.html
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: _startDrag,
              onVerticalDragUpdate: _updateDrag,
              onVerticalDragEnd: _endDrag,
              onVerticalDragCancel: () => _dragStartY = null,
              child: Padding(
                padding: const EdgeInsets.only(bottom: DoableMetrics.space3),
                child: header,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space2,
            ),
            child: expansion.pinned,
          ),
          const SizedBox(height: DoableMetrics.space2),
          Expanded(child: widget.body),
        ],
      ),
      footer: _Footer(child: expansion.footer),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Высота ограничена местом над клавиатурой: его отнимает
        // _SheetFrame, а полный лист занимает всё оставшееся.
        final full = constraints.maxHeight;
        final half = math.min(_halfHeight, full);
        return AnimatedBuilder(
          animation: _expansion,
          builder: (context, child) {
            final progress = _expansion.value;
            final borderRadius = BorderRadius.vertical(
              top: Radius.circular(
                lerpDouble(DoableMetrics.radiusXl, 0, progress)!,
              ),
            );
            return SizedBox(
              height: lerpDouble(half, full, progress),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  boxShadow: BoxShadow.lerpList(
                    shadows.shadowFloat,
                    null,
                    progress,
                  ),
                ),
                child: Material(
                  color: colors.raised,
                  borderRadius: borderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
            );
          },
          child: content,
        );
      },
    );
  }
}

final class _Grip extends StatelessWidget {
  const _Grip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(DoableMetrics.radiusFull),
    ),
  );
}

final class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.text,
    required this.action,
  });

  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsOf(Theme.of(context));
    return _TitleLayout(
      title: Semantics(
        header: true,
        namesRoute: true,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: DoableType.title.copyWith(color: colors.ink),
        ),
      ),
      action: action,
      text: switch (text) {
        final text? => Padding(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: DoableType.hint.copyWith(color: colors.muted),
          ),
        ),
        null => null,
      },
    );
  }
}

enum _TitleSlot { title, action, text }

/// Заголовок по центру, действие справа на его строке и пояснение под ним.
///
/// Заголовок отступает от обоих краёв на ширину действия, поэтому остаётся
/// по центру и не заходит под действие. Область нажатия действия выше строки
/// заголовка и выходит за верх раскладки; там она тоже принимает касания.
final class _TitleLayout
    extends SlottedMultiChildRenderObjectWidget<_TitleSlot, RenderBox> {
  const _TitleLayout({
    required this.title,
    required this.action,
    required this.text,
  });

  final Widget title;
  final Widget? action;
  final Widget? text;

  @override
  Iterable<_TitleSlot> get slots => _TitleSlot.values;

  @override
  Widget? childForSlot(_TitleSlot slot) => switch (slot) {
    _TitleSlot.title => title,
    _TitleSlot.action => action,
    _TitleSlot.text => text,
  };

  @override
  _RenderTitleLayout createRenderObject(BuildContext context) =>
      _RenderTitleLayout();
}

final class _RenderTitleLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<_TitleSlot, RenderBox> {
  static const _textGap = 2.0;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final title = childForSlot(_TitleSlot.title)!;
    final action = childForSlot(_TitleSlot.action);
    final text = childForSlot(_TitleSlot.text);

    action?.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final inset = action?.size.width ?? 0;
    title.layout(
      BoxConstraints.tightFor(width: math.max(0, width - 2 * inset)),
      parentUsesSize: true,
    );
    _place(title, Offset(inset, 0));
    if (action != null) {
      _place(
        action,
        Offset(
          width - action.size.width,
          (title.size.height - action.size.height) / 2,
        ),
      );
    }
    var height = title.size.height;
    if (text != null) {
      text.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height += _textGap;
      _place(text, Offset(0, height));
      height += text.size.height;
    }
    size = constraints.constrain(Size(width, height));
  }

  static void _place(RenderBox child, Offset offset) =>
      (child.parentData! as BoxParentData).offset = offset;

  static Offset _offsetOf(RenderBox child) =>
      (child.parentData! as BoxParentData).offset;

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(child, offset + _offsetOf(child));
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final action = childForSlot(_TitleSlot.action);
    final isInside =
        size.contains(position) ||
        (action != null &&
            (_offsetOf(action) & action.size).contains(position));
    if (!isInside || !hitTestChildren(result, position: position)) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final isHit = result.addWithPaintOffset(
        offset: _offsetOf(child),
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (isHit) return true;
    }
    return false;
  }
}

final class _Footer extends StatelessWidget {
  const _Footer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space2,
      DoableMetrics.space3,
      DoableMetrics.space2,
      0,
    ),
    child: child,
  );
}

DoableColors _colorsOf(ThemeData theme) =>
    theme.extension<DoableColors>() ??
    switch (theme.brightness) {
      Brightness.light => DoableColors.light,
      Brightness.dark => DoableColors.dark,
    };

DoableShadows _shadowsOf(ThemeData theme) =>
    theme.extension<DoableShadows>() ??
    switch (theme.brightness) {
      Brightness.light => DoableShadows.light,
      Brightness.dark => DoableShadows.dark,
    };
