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

/// Возможность построить [Sheet] или [Sheet.expandable].
///
/// Её даёт построителю только [showDoableSheet]: она несёт маршрут этой
/// функции, анимацию которого лист ведёт пальцем.
final class SheetPresentation {
  const SheetPresentation._(this._route);

  final _DoableSheetRoute<Object?> _route;
}

/// Показывает лист над корневым навигатором, перекрывая всю страницу и
/// панель.
///
/// [builder] строит [Sheet], [Sheet.expandable] или композицию на их основе с
/// переданной возможностью. Потребитель закрывает лист через Navigator.pop с
/// результатом типа [T]; закрытие без выбора даёт null. Лист перетаскивает сам
/// [Sheet], а затемнение, системное «назад», фокус и семантика маршрута
/// принадлежат модальной нижней панели Material:
/// https://api.flutter.dev/flutter/material/ModalBottomSheetRoute-class.html
///
/// С [hostsMessages] лист содержит собственный прозрачный [Scaffold], и
/// сообщения общего [ScaffoldMessenger] появляются над его нижней частью, а не
/// на странице под листом. Признак нужен листу, который остаётся открытым до
/// результата начатой в нём операции.
Future<T?> showDoableSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, SheetPresentation sheet)
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
        child: builder(context, SheetPresentation._(route)),
      ),
    ),
  );
  return navigator.push(route);
}

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

/// Маршрут листа: модальная нижняя панель Material без её перетаскивания,
/// анимацию которой ведёт пальцем [_SheetMotion].
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

/// Раскрытие листа над компактным размером, которое ведёт [_SheetMotion].
final class _SheetExpansion {
  const _SheetExpansion({
    required this.controller,
    required this.extents,
    required this.inset,
    required this.isFull,
    required this.resize,
  });

  /// 0 — компактный размер, 1 — полный.
  final AnimationController controller;

  /// Компактная и полная высота листа при последней раскладке.
  final _ExpandableExtents extents;

  /// Отступ открытой клавиатуры под листом.
  final double inset;

  /// На сколько полный размер выше компактного; 0, когда листу некуда расти.
  double get length => extents.full - extents.compact;

  /// Высота, на которую маршрут уводит компактный лист при закрытии.
  double get compactExtent => extents.compact + inset;

  /// Размер, в котором лист стоит или к которому идёт.
  final bool isFull;

  /// Доводит лист до размера [full].
  final void Function({required bool full}) resize;
}

enum _SheetState { closed, compact, full }

/// Ведёт лист пальцем между закрытым, компактным и, с [expansion], полным
/// размером и после отпускания доводит его до одного из них.
///
/// Положение листа — сдвиг верхнего края от компактного положения: ниже него
/// это значение маршрута после [_sheetCurve], выше — раскрытие [expansion].
/// Пороги скорости и положения — те же, что у перетаскивания модальной нижней
/// панели Material.
///
/// Лист ведёт палец на его поверхности и на теле, которое [builder]
/// подключает к переданному контроллеру прокрутки.
final class _SheetMotion extends StatefulWidget {
  const _SheetMotion({
    required this.route,
    required this.expansion,
    required this.builder,
  });

  final _DoableSheetRoute<Object?> route;

  /// Раскрытие листа; без него лист — по содержимому.
  final _SheetExpansion? expansion;

  /// Строит лист с контроллером прокрутки его тела.
  final Widget Function(ScrollController body) builder;

  @override
  State<_SheetMotion> createState() => _SheetMotionState();
}

final class _SheetMotionState extends State<_SheetMotion> {
  static const _flingVelocity = 700.0;
  static const _closePosition = 0.5;

  late final _body = _SheetBodyController(this);

  /// Сдвиг листа и его размер в начале текущего жеста.
  late ({double offset, bool isFull}) _drag;

  /// Сумма сдвигов вниз, на которые лист прошёл за текущий жест.
  ///
  /// После принятия жеста распознаватель поверхности передаёт сдвиги
  /// отслеживаемого пальца и переходит к другому без скачка, поэтому лист не
  /// сдвигается на расстояние между пальцами:
  /// https://api.flutter.dev/flutter/gestures/MultitouchDragStrategy.html#latestPointer
  ///
  /// До принятия жеста палец ещё не выбран, и первое обновление несёт сумму
  /// сдвигов всех пальцев на листе. Если за касание соперничает другой
  /// элемент листа и два пальца двигались до принятия, лист один раз
  /// смещается и на сдвиг второго пальца.
  ///
  /// Тело добавляет только ту часть своего сдвига, которую лист принял.
  var _distance = 0.0;
  var _isPointerCanceled = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  _DoableSheetRoute<Object?> get _route => widget.route;

  /// Длина отрезка раскрытия; 0, когда лист не раскрывается или ему некуда
  /// расти.
  double get _growth => widget.expansion?.length ?? 0;

  double get _compactExtent =>
      widget.expansion?.compactExtent ?? _route._extent;

  double get _position => _sheetCurve.transform(_route._animation.value);

  /// Раскрытие листа: 0 — компактный размер, 1 — полный.
  double get _expansion => widget.expansion?.controller.value ?? 0;

  /// Сдвиг верхнего края листа вверх от компактного положения: отрицательный
  /// на отрезке сдвига, положительный на отрезке раскрытия.
  double get _offset => _route._animation.value < 1
      ? (_position - 1) * _compactExtent
      : (widget.expansion?.controller.value ?? 0) * _growth;

  /// Сдвиг листа, на который его ставит текущий жест.
  double get _dragOffset =>
      clampDouble(_drag.offset - _distance, -_compactExtent, _growth);

  void _startDrag() {
    _drag = (offset: _offset, isFull: widget.expansion?.isFull ?? false);
    _distance = 0;
    _isPointerCanceled = false;
  }

  void _updateDrag(DragUpdateDetails details) {
    // Закрывающийся маршрут доводит анимацию сам, а запись значения её
    // остановила бы.
    if (!_route.isCurrent) return;
    _distance += details.delta.dy;
    _place();
  }

  /// Сдвигает лист за пальцем на теле на [delta] вниз, насколько лист может
  /// пройти, и возвращает пройденную часть.
  double _follow(double delta) {
    final offset = _dragOffset;
    final target = clampDouble(offset - delta, -_compactExtent, _growth);
    if (target == offset) return 0;
    _distance = _drag.offset - target;
    _place();
    return offset - target;
  }

  void _place() {
    // Положение вычисляется от начала жеста, а не накапливается из
    // приращений значения, поэтому ошибка обратной функции кривой не
    // накапливается.
    final offset = _dragOffset;
    if (widget.expansion case final expansion? when _growth > 0) {
      expansion.controller.value = math.max(offset, 0) / _growth;
    }
    _route._animation.value = _inverseSheetCurve(
      1 + math.min(offset, 0) / _compactExtent,
    );
  }

  /// Доводит лист после отпускания пальца со скоростью [velocity] вниз.
  void _endDrag(double velocity) {
    // Закрыв или перекрыв лист во время жеста, Navigator отменяет касания, и
    // жест завершается здесь. Доводка тогда остановила бы закрытие, а
    // Navigator.pop закрыл бы маршрут под листом.
    if (!_route.isCurrent) return;
    // Принятый жест Flutter завершает через onEnd даже при PointerCancelEvent:
    // https://api.flutter.dev/flutter/gestures/DragGestureRecognizer/didStopTrackingLastPointer.html
    final target = _isPointerCanceled ? _startState : _targetOf(velocity);
    switch (target) {
      case _SheetState.closed:
        Navigator.pop(context);
      case _SheetState.compact || _SheetState.full:
        _route._animation.forward();
        widget.expansion?.resize(full: target == _SheetState.full);
    }
  }

  /// Состояние, к которому лист идёт после отпускания со скоростью
  /// [velocity] вниз.
  _SheetState _targetOf(double velocity) {
    final offset = _offset;
    final target = switch (velocity) {
      > _flingVelocity => offset > 0 ? _SheetState.compact : _SheetState.closed,
      < -_flingVelocity => offset < 0 ? _SheetState.compact : _SheetState.full,
      _ when offset < 0 =>
        _position < _closePosition ? _SheetState.closed : _SheetState.compact,
      _ => offset < _growth / 2 ? _SheetState.compact : _SheetState.full,
    };
    // Без отрезка раскрытия жест не меняет размер листа.
    return _growth == 0 && target != _SheetState.closed ? _startState : target;
  }

  _SheetState get _startState =>
      _drag.isFull ? _SheetState.full : _SheetState.compact;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: (_) => _isPointerCanceled = true,
    child: GestureDetector(
      // Лист под пальцем стоит той точкой, которой его коснулись:
      // https://api.flutter.dev/flutter/gestures/DragStartBehavior.html
      dragStartBehavior: DragStartBehavior.down,
      // Как у модальной нижней панели Material, перетаскивание не
      // объявляется диктору прокруткой.
      excludeFromSemantics: true,
      onVerticalDragStart: (_) => _startDrag(),
      onVerticalDragUpdate: _updateDrag,
      onVerticalDragEnd: (details) =>
          _endDrag(details.velocity.pixelsPerSecond.dy),
      child: widget.builder(_body),
    ),
  );
}

final class _SheetBodyController extends ScrollController {
  _SheetBodyController(this._motion);

  final _SheetMotionState _motion;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetBodyPosition(
    motion: _motion,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

/// Позиция прокрутки тела листа, которая до прокрутки предлагает листу
/// каждый сдвиг пальца: вниз тело сначала прокручивается к своему началу, а
/// остаток опускает лист; вверх сначала поднимается лист, насколько может, а
/// остаток прокручивает тело.
///
/// Это схема позиции DraggableScrollableSheet:
/// https://api.flutter.dev/flutter/widgets/DraggableScrollableSheet-class.html
final class _SheetBodyPosition extends ScrollPositionWithSingleContext {
  _SheetBodyPosition({
    required this._motion,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _SheetMotionState _motion;

  /// Ведёт ли текущее перетаскивание палец.
  var _isFingerDrag = false;

  /// Сдвинулся ли лист в текущем перетаскивании.
  var _hasSheetMoved = false;

  /// Подъём раскрытого листа над компактным размером при последней
  /// раскладке тела.
  var _laidOutRise = 0.0;

  /// Подъём раскрытого листа над компактным размером. Раскрытие без места для
  /// роста его не меняет, и тело тогда заново не раскладывается.
  double get _rise => _motion._expansion * _motion._growth;

  @override
  bool applyViewportDimension(double viewportDimension) {
    _laidOutRise = _rise;
    return super.applyViewportDimension(viewportDimension);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    // Действия прокрутки диктора Flutter выполняет обработчиками
    // перетаскивания списка, но без устройства ввода:
    // https://api.flutter.dev/flutter/gestures/DragStartDetails/kind.html
    _isFingerDrag = details.kind != null;
    _hasSheetMoved = false;
    if (_isFingerDrag) _motion._startDrag();
    return super.drag(details, dragCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    if (!_isFingerDrag) {
      super.applyUserOffset(delta);
      return;
    }
    final scroll = delta > 0
        ? math.min(delta, math.max(pixels - minScrollExtent, 0.0))
        : 0.0;
    if (scroll > 0) super.applyUserOffset(scroll);
    final moved = _motion._follow(delta - scroll);
    if (moved != 0) _hasSheetMoved = true;
    // Остаток вниз бывает, только когда лист опущен до конца пути, и он
    // гасится. Остаток вверх тело, которое помещается целиком, гасит без
    // эффекта края. Гасится он и тогда, когда тело ещё не разложено в
    // новой высоте раскрытого листа: его предел прокрутки устарел.
    final rest = delta - scroll - moved;
    if (rest < 0 &&
        maxScrollExtent > minScrollExtent &&
        _rise == _laidOutRise) {
      super.applyUserOffset(rest);
    }
  }

  @override
  void goBallistic(double velocity) {
    // Перетаскивание завершается здесь отпусканием или отменой.
    final settlesSheet = _isFingerDrag && _hasSheetMoved;
    _isFingerDrag = false;
    if (!settlesSheet) {
      super.goBallistic(velocity);
      return;
    }
    // Скорость прокрутки направлена к концу тела, то есть вверх.
    _motion._endDrag(-velocity);
    // Тело не прокручивается по инерции, когда жест вёл лист.
    super.goBallistic(0);
  }
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
/// Оба варианта листа строятся только с возможностью, которую даёт
/// построителю [showDoableSheet].
final class Sheet extends StatelessWidget {
  /// Лист высотой по содержимому.
  ///
  /// Лист перетаскивается за шапку, нижнюю часть и тело и закрывается жестом
  /// вниз; касание затемнения и «назад» закрывают его средствами Material
  /// маршрута [showDoableSheet]. При нехватке высоты прокручивается только
  /// тело, а нижняя часть видна под ним. Тело передаёт жест листу: движение
  /// вниз прокручивает его к началу, а от начала опускает лист.
  ///
  /// [text] — пояснение под заголовком; без него тело следует сразу за
  /// заголовком. [footer] — основная кнопка листа на всю ширину, закреплённая
  /// под телом вне его прокрутки; без неё лист заканчивается телом.
  Sheet(
    this._presentation, {
    required this.title,
    required Widget child,
    String? text,
    Widget? footer,
    super.key,
  }) : _parts = _ContentParts(text: text, body: child, footer: footer);

  /// Лист компактной высоты, который раскрывается на весь экран.
  ///
  /// [compactHeight] — компактная высота: весь предел или высота содержимого
  /// в пределе. Рост содержимого лист не раскрывает: раскрывает его только
  /// пользователь.
  /// Лист перетаскивается за шапку, [pinned], [footer] и список: выше
  /// компактного размера он растёт, а [footer] стоит на месте, ниже — уходит
  /// целиком. После отпускания он раскрывается, сворачивается или
  /// закрывается по положению и скорости; нажатие на ручку переключает
  /// размер. Касание затемнения и «назад» закрывают лист средствами Material
  /// маршрута [showDoableSheet].
  /// [slivers] — срезы тела, из которых лист сам строит прокручиваемый
  /// список между шапкой и [footer]. Список передаёт жест листу: в
  /// компактном размере движение вверх сначала раскрывает лист, а движение
  /// вниз прокручивает список к началу, а от начала сворачивает и опускает
  /// лист. [pinned] — необязательные неподвижные части между шапкой и
  /// списком; без них список следует сразу за шапкой.
  /// [expandLabel] и [collapseLabel] — доступные названия ручки.
  /// [action] — текстовая кнопка размера sm справа на строке заголовка,
  /// например «Сбросить»; заголовок при ней остаётся по центру.
  Sheet.expandable(
    this._presentation, {
    required this.title,
    required String text,
    required SheetCompactHeight compactHeight,
    required List<Widget> slivers,
    required Widget footer,
    required String expandLabel,
    required String collapseLabel,
    Widget? pinned,
    SheetAction? action,
    super.key,
  }) : _parts = _ExpandableParts(
         text: text,
         compactHeight: compactHeight,
         pinned: pinned,
         slivers: slivers,
         footer: footer,
         expandLabel: expandLabel,
         collapseLabel: collapseLabel,
         action: action,
       );

  final String title;

  final SheetPresentation _presentation;

  /// Части листа, которые определяют его вариант.
  final _SheetParts _parts;

  @override
  Widget build(BuildContext context) => switch (_parts) {
    final _ContentParts parts => _buildContent(context, parts),
    final _ExpandableParts parts => _ExpandableSheet(
      route: _presentation._route,
      title: title,
      parts: parts,
    ),
  };

  Widget _buildContent(BuildContext context, _ContentParts parts) {
    final theme = Theme.of(context);
    final colors = _colorsOf(theme);
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(DoableMetrics.radiusXl),
    );

    return _SheetMotion(
      route: _presentation._route,
      expansion: null,
      builder: (body) => DecoratedBox(
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
                _TitleBlock(title: title, text: parts.text, action: null),
                const SizedBox(height: DoableMetrics.space3),
                Flexible(
                  child: SingleChildScrollView(
                    controller: body,
                    // Тело, которое помещается целиком, тоже передаёт жест
                    // листу.
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: parts.body,
                  ),
                ),
              ],
            ),
            footer: switch (parts.footer) {
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
          // Нижняя часть стоит внизу листа, даже когда содержимое над ней
          // ниже его высоты.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

/// Компактная высота раскрываемого листа.
enum SheetCompactHeight {
  /// Весь предел компактной высоты.
  limit,

  /// Высота содержимого листа, но не больше предела компактной высоты.
  content,
}

/// Предел компактной высоты раскрываемого листа; лист не выше доступного
/// места.
const _compactLimit = 534.0;

/// Части листа одного из двух вариантов.
sealed class _SheetParts {
  const _SheetParts();
}

/// Части листа по содержимому.
final class _ContentParts extends _SheetParts {
  const _ContentParts({
    required this.text,
    required this.body,
    required this.footer,
  });

  final String? text;
  final Widget body;
  final Widget? footer;
}

/// Части раскрываемого листа.
final class _ExpandableParts extends _SheetParts {
  const _ExpandableParts({
    required this.text,
    required this.compactHeight,
    required this.pinned,
    required this.slivers,
    required this.footer,
    required this.expandLabel,
    required this.collapseLabel,
    required this.action,
  });

  final String text;
  final SheetCompactHeight compactHeight;
  final Widget? pinned;

  /// Срезы прокручиваемого списка тела.
  final List<Widget> slivers;
  final Widget footer;
  final String expandLabel;
  final String collapseLabel;
  final SheetAction? action;
}

final class _ExpandableSheet extends StatefulWidget {
  const _ExpandableSheet({
    required this.route,
    required this.title,
    required this.parts,
  });

  final _DoableSheetRoute<Object?> route;
  final String title;
  final _ExpandableParts parts;

  @override
  State<_ExpandableSheet> createState() => _ExpandableSheetState();
}

final class _ExpandableSheetState extends State<_ExpandableSheet>
    with SingleTickerProviderStateMixin {
  final _extents = _ExpandableExtents();

  /// 0 — компактный размер, 1 — весь экран.
  late final _expansion = AnimationController(
    vsync: this,
    duration: _sheetDuration,
  );
  var _isFull = false;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colorsOf(theme);
    final shadows = _shadowsOf(theme);
    final parts = widget.parts;

    final handle = Semantics(
      container: true,
      button: true,
      expanded: _isFull,
      label: _isFull ? parts.collapseLabel : parts.expandLabel,
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
      text: parts.text,
      action: switch (parts.action) {
        final action? => Button.text(
          label: action.label,
          semanticLabel: action.semanticLabel,
          onPressed: action.onPressed,
        ),
        null => null,
      },
    );
    // Ручка компактного листа стоит над началом заголовка, чтобы область
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

    final pinned = parts.pinned;
    final shrinkWrap = switch (parts.compactHeight) {
      SheetCompactHeight.limit => false,
      // Список высотой по содержимому даёт листу компактную высоту.
      SheetCompactHeight.content => true,
    };
    Widget content(ScrollController body) {
      final list = CustomScrollView(
        controller: body,
        // Список, который помещается целиком, тоже передаёт жест листу.
        physics: const AlwaysScrollableScrollPhysics(),
        shrinkWrap: shrinkWrap,
        slivers: parts.slivers,
      );
      return _SheetLayout(
        minimum: const EdgeInsets.symmetric(horizontal: DoableMetrics.space3),
        head: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: DoableMetrics.space3),
              child: header,
            ),
            if (pinned != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DoableMetrics.space2,
                ),
                child: pinned,
              ),
              const SizedBox(height: DoableMetrics.space2),
            ],
            if (shrinkWrap) Flexible(child: list) else Expanded(child: list),
          ],
        ),
        footer: _Footer(child: parts.footer),
      );
    }

    return _SheetMotion(
      route: widget.route,
      expansion: _SheetExpansion(
        controller: _expansion,
        extents: _extents,
        inset: MediaQuery.viewInsetsOf(context).bottom,
        isFull: _isFull,
        resize: _resize,
      ),
      builder: (body) => AnimatedBuilder(
        animation: _expansion,
        builder: (context, child) {
          final progress = _expansion.value;
          final borderRadius = BorderRadius.vertical(
            top: Radius.circular(
              lerpDouble(DoableMetrics.radiusXl, 0, progress)!,
            ),
          );
          return _ExpandableFrame(
            compactHeight: parts.compactHeight,
            progress: progress,
            extents: _extents,
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
        child: content(body),
      ),
    );
  }
}

/// Компактная и полная высота раскрываемого листа при последней раскладке.
final class _ExpandableExtents {
  var compact = 0.0;
  var full = 0.0;
}

/// Ставит раскрываемый лист в высоту между компактной и полной по раскрытию
/// [progress] и записывает обе высоты в [extents].
///
/// Полный лист занимает всё место над клавиатурой: его отнимает _SheetFrame.
/// С [SheetCompactHeight.content] лист сначала раскладывается без строгой
/// высоты в пределе, и занятая им высота — компактная; затем, если раскрыт,
/// — повторно в свою высоту.
final class _ExpandableFrame extends SingleChildRenderObjectWidget {
  const _ExpandableFrame({
    required this.compactHeight,
    required this.progress,
    required this.extents,
    required super.child,
  });

  final SheetCompactHeight compactHeight;

  /// 0 — компактный размер, 1 — полный.
  final double progress;
  final _ExpandableExtents extents;

  @override
  _RenderExpandableFrame createRenderObject(BuildContext context) =>
      _RenderExpandableFrame(compactHeight, progress, extents);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExpandableFrame renderObject,
  ) => renderObject
    ..compactHeight = compactHeight
    ..progress = progress
    ..extents = extents;
}

final class _RenderExpandableFrame extends RenderProxyBox {
  _RenderExpandableFrame(this._compactHeight, this._progress, this.extents);

  _ExpandableExtents extents;

  SheetCompactHeight _compactHeight;

  set compactHeight(SheetCompactHeight value) {
    if (value == _compactHeight) return;
    _compactHeight = value;
    markNeedsLayout();
  }

  double _progress;

  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Компактная высота листа зависит от раскладки его содержимого.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    final sheet = child!;
    final full = constraints.maxHeight;
    final limit = math.min(_compactLimit, full);
    // Ширина нестрогая, поэтому лист не становится границей раскладки, и
    // изменение содержимого снова доходит до компактной высоты.
    final width = constraints.maxWidth;
    final double compact;
    switch (_compactHeight) {
      case SheetCompactHeight.limit:
        compact = limit;
      case SheetCompactHeight.content:
        sheet.layout(
          BoxConstraints(maxWidth: width, maxHeight: limit),
          parentUsesSize: true,
        );
        compact = sheet.size.height;
    }
    extents
      ..compact = compact
      ..full = full;
    final height = lerpDouble(compact, full, _progress)!;
    if (_compactHeight == SheetCompactHeight.limit || height != compact) {
      sheet.layout(
        BoxConstraints(maxWidth: width, minHeight: height, maxHeight: height),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(sheet.size);
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
