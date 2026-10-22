import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';

/// Размер листа, с которым его показывает [showDoableSheet].
enum DoableSheetSize {
  /// Высота по содержимому; лист целиком перетаскивает Material.
  content,

  /// Половинная высота с раскрытием на весь экран жестом и нажатием шапки;
  /// содержимое — [Sheet.expandable].
  expandable,
}

/// Показывает лист над корневым навигатором, перекрывая всю страницу и панель.
///
/// [builder] строит [Sheet] или композицию на его основе; для
/// [DoableSheetSize.expandable] — на основе [Sheet.expandable]. Потребитель
/// закрывает лист через Navigator.pop с результатом типа [T]; закрытие без
/// выбора даёт null. Барьер, системное «назад» и семантика маршрута
/// принадлежат Material, а жест закрытия — Material только у листа по
/// содержимому:
/// https://api.flutter.dev/flutter/material/showModalBottomSheet.html
///
/// С [hostsMessages] лист содержит собственный прозрачный [Scaffold], и
/// сообщения общего [ScaffoldMessenger] появляются над его нижней частью, а не
/// на странице под листом. Признак нужен листу, который остаётся открытым до
/// результата начатой в нём операции.
Future<T?> showDoableSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DoableSheetSize size = DoableSheetSize.content,
  bool hostsMessages = false,
}) {
  final colors = _colorsOf(Theme.of(context));

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    barrierColor: colors.scrim,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    // Лист занимает всю доступную ширину, без ограничения Material 3 в 640 dp.
    constraints: const BoxConstraints(maxWidth: double.infinity),
    showDragHandle: false,
    isDismissible: true,
    // Раскрываемый лист сам обрабатывает перетаскивание шапки.
    enableDrag: switch (size) {
      DoableSheetSize.content => true,
      DoableSheetSize.expandable => false,
    },
    builder: (context) => Padding(
      // SafeArea учитывает системные панели, но не открытую клавиатуру.
      // https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: hostsMessages
          ? _MessagesHost(child: builder(context))
          : builder(context),
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

/// Лист с ручкой, заголовком, пояснением, телом и нижней частью.
///
/// Компонент только оформляет содержимое, показом управляет [showDoableSheet].
final class Sheet extends StatelessWidget {
  /// Лист высотой по содержимому.
  ///
  /// При нехватке высоты прокручивается только тело: шапка остаётся доступной
  /// для свайпа, а нижняя часть — видна под телом.
  const Sheet({
    required this.title,
    required this.child,
    this.text,
    this.footer,
    super.key,
  }) : _expansion = null;

  /// Лист половинной высоты, который раскрывается на весь экран.
  ///
  /// Перетаскивание шапки на 48 вверх раскрывает лист, вниз — сворачивает
  /// полный или закрывает половинный; нажатие на ручку переключает размер.
  /// [body] — собственный прокручиваемый список тела, который занимает место
  /// между [pinned] и [footer]; его прокрутка не меняет размер листа.
  /// [expandLabel] и [collapseLabel] — доступные названия ручки.
  const Sheet.expandable({
    required this.title,
    required String text,
    required Widget pinned,
    required Widget body,
    required Widget footer,
    required String expandLabel,
    required String collapseLabel,
    super.key,
  }) : text = text,
       child = body,
       footer = footer,
       _expansion = (
         text: text,
         pinned: pinned,
         footer: footer,
         expandLabel: expandLabel,
         collapseLabel: collapseLabel,
       );

  final String title;

  /// Пояснение под заголовком; без него тело следует сразу за заголовком.
  final String? text;

  /// Тело листа.
  final Widget child;

  /// Основная кнопка листа на всю ширину, закреплённая под телом вне его
  /// прокрутки; без неё лист заканчивается телом.
  final Widget? footer;

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

    return DecoratedBox(
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
              _TitleBlock(title: title, text: text),
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
/// следует за [head] и [footer], а клавиатуру учитывает только
/// [showDoableSheet].
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
    duration: const Duration(milliseconds: 180),
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
    final titleBlock = _TitleBlock(title: widget.title, text: expansion.text);
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
        // showDoableSheet, а полный лист занимает всё оставшееся.
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
  const _TitleBlock({required this.title, required this.text});

  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsOf(Theme.of(context));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          namesRoute: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: DoableType.title.copyWith(color: colors.ink),
          ),
        ),
        if (text case final text?) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space4,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          ),
        ],
      ],
    );
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
