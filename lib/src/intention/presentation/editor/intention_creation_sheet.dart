import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Модальная нижняя панель создания намерения над страницей, с которой
/// начато создание.
///
/// Панель отвечает за модальность, адаптивную геометрию и прокрутку:
/// модальный фон над страницей под ней, высоту по содержимому в пределах
/// доступной области с видимым участком страницы над панелью, закреплённые
/// ручку и основное действие и вход и выход вместе со своим маршрутом.
/// В тесной области закрытие и основные действия делят верхнюю полосу,
/// оставляя место вводу без изменения дерева полей и их прокрутки.
/// Доступная область учитывает клавиатуру и безопасные отступы.
///
/// Свайп вниз по ручке, нажатие вне панели, кнопка закрытия и действие
/// экранного диктора передаются через [onCloseRequested]. Сама панель свой
/// маршрут не закрывает. Свайп вверх по ручке ничего не запускает;
/// прокрутка полей панель не закрывает.
///
/// Закреплённое сообщение [status] стоит после полей и
/// остаётся видимым при любой прокрутке полей. По запросу [reveal] панель
/// доводит часть полей до видимости и удерживает её видимой при пересчёте
/// своей геометрии.
///
/// Поля лежат в собственном `Scaffold` панели, поэтому сообщение общей
/// поверхности приложения видно поверх нижнего края полей и не перекрывает
/// закреплённое сообщение и нижнюю часть.
final class IntentionCreationSheet extends StatefulWidget {
  const IntentionCreationSheet({
    required this.onCloseRequested,
    required this.closeLabel,
    required this.header,
    required this.fields,
    required this.footer,
    this.status,
    this.reveal,
    super.key,
  });

  /// Запрос закрытия: кнопкой, свайпом вниз по ручке, нажатием
  /// вне панели или действием экранного диктора.
  final VoidCallback onCloseRequested;

  /// Подсказка кнопки закрытия и доступное название модального фона.
  final String closeLabel;

  /// Заголовок формы. Прокручивается вместе с полями, чтобы при тесной
  /// доступной области место оставалось полям.
  final Widget header;

  /// Поля формы. Прокручиваются, когда не помещаются в доступную высоту.
  final Widget fields;

  /// Закреплённые действия формы; при нехватке высоты стоят рядом с ручкой.
  final Widget footer;

  /// Закреплённое после полей сообщение, например общий отказ
  /// сохранения. При нехватке высоты полям остаётся всё нужное им место, но
  /// не больше половины, а сообщение занимает остальное и прокручивается
  /// само, начиная с первой строки.
  final Widget? status;

  /// Запрос держать видимой часть полей, например поле с ошибкой.
  ///
  /// Панель доводит цель до видимости после ближайшего кадра и снова — при
  /// каждом изменении размеров своих прокручиваемых областей: при появлении
  /// клавиатуры или росте содержимого. Запрос действует, пока
  /// владелец его не сменит или не снимет и пока человек сам не прокрутит
  /// панель; обычная прокрутка к каретке поля его не прекращает.
  final IntentionCreationSheetReveal? reveal;

  @override
  State<IntentionCreationSheet> createState() => _IntentionCreationSheetState();
}

/// Запрос держать видимой часть полей панели. Каждый новый объект — новый
/// запрос, даже для той же цели.
final class IntentionCreationSheetReveal {
  IntentionCreationSheetReveal(this.target);

  /// Ключ виджета внутри полей панели.
  final GlobalKey target;
}

final class _IntentionCreationSheetState extends State<IntentionCreationSheet> {
  /// Участок страницы под строкой состояния, который компактная панель
  /// оставляет видимым при любой высоте содержимого: контекст, над которым
  /// открыто создание. Это отступ, а не доля экрана.
  static const _visibleContextExtent = 72.0;

  /// Наименьший видимый участок страницы над компактной панелью. До него
  /// участок уступает место закреплённым частям панели и наименьшей видимой
  /// области полей, когда клавиатура, альбомная ориентация или увеличенный
  /// текст оставляют слишком мало высоты.
  static const _minVisibleContextExtent = 24.0;

  /// Наибольшая ширина панели на широком экране.
  static const _maxWidth = 640.0;

  /// Скорость, начиная с которой короткий свайп по ручке считается
  /// запросом закрытия.
  static const _minFlingVelocity = 700.0;

  /// Путь медленного свайпа по ручке, начиная с которого он считается
  /// запросом закрытия.
  static const _minDragDistance = 40.0;

  var _dragDistance = 0.0;

  /// Запрос видимости, который панель ещё выполняет.
  IntentionCreationSheetReveal? _activeReveal;

  /// Последние размеры области и содержимого каждой прокручиваемой области
  /// панели: доведение до видимости повторяется при их изменении, но не при
  /// прокрутке.
  final _scrollExtents = Expando<(double, double)>();

  @override
  void initState() {
    super.initState();
    _startReveal();
  }

  @override
  void didUpdateWidget(IntentionCreationSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.reveal, oldWidget.reveal)) {
      _startReveal();
    }
  }

  void _startReveal() {
    final reveal = _activeReveal = widget.reveal;
    if (reveal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _keepVisible(reveal));
    }
  }

  void _keepVisible(IntentionCreationSheetReveal reveal) {
    final target = reveal.target.currentContext;
    if (!mounted || !identical(reveal, _activeReveal) || target == null) {
      return;
    }
    // Сначала начало цели, затем её конец: цель выше видимой области
    // показывается с начала, а не помещающаяся целиком — концом, где у поля
    // находится текст ошибки.
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ]) {
      unawaited(Scrollable.ensureVisible(target, alignmentPolicy: policy));
    }
  }

  /// Прокрутка человеком прекращает запрос видимости. Программная прокрутка,
  /// например к каретке поля, его не прекращает.
  bool _handleScroll(ScrollNotification notification) {
    final isUserScroll = switch (notification) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      UserScrollNotification(:final direction) =>
        direction != ScrollDirection.idle,
      _ => false,
    };
    if (isUserScroll) {
      _activeReveal = null;
    }
    return false;
  }

  /// Повторяет доведение до видимости после изменения размеров области или
  /// содержимого. Уведомление приходит после кадра, поэтому повтор идёт
  /// после прокрутки к каретке поля, которую в том же кадре запускает
  /// появление клавиатуры.
  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    final extents = (
      metrics.viewportDimension,
      metrics.maxScrollExtent - metrics.minScrollExtent,
    );
    final previous = _scrollExtents[notification.context];
    _scrollExtents[notification.context] = extents;
    if (previous != null && previous != extents) {
      if (_activeReveal case final reveal?) {
        _keepVisible(reveal);
      }
    }
    return false;
  }

  void _startDrag(DragStartDetails details) => _dragDistance = 0;

  void _updateDrag(DragUpdateDetails details) =>
      _dragDistance += details.primaryDelta ?? 0;

  /// Достаточный свайп вниз запрашивает закрытие; свайп вверх бездействует.
  /// Скорость завершения жеста передаёт GestureDetector:
  /// https://api.flutter.dev/flutter/widgets/GestureDetector/onVerticalDragEnd.html
  void _endDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final direction = velocity.abs() >= _minFlingVelocity
        ? velocity.sign
        : _dragDistance.abs() >= _minDragDistance
        ? _dragDistance.sign
        : 0.0;
    if (direction > 0) {
      widget.onCloseRequested();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final animation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фон закрывает страницу под панелью от нажатий, а модальный барьер
        // маршрута — от фокуса и экранного диктора.
        //
        // Фон во весь экран и панель — отдельные узлы экранного диктора с
        // явным порядком. Иначе фон собирает узлы панели вместе с собой в
        // одну группу обхода, и диктор упорядочивает их по углам между
        // центрами: от высоты панели зависело бы, прочтёт ли он закрытие до
        // полей или после них.
        Semantics(
          container: true,
          sortKey: const OrdinalSortKey(0),
          child: FadeTransition(
            opacity: animation,
            child: ModalBarrier(
              color: colors.scrim.withValues(alpha: 0.32),
              semanticsLabel: widget.closeLabel,
              onDismiss: widget.onCloseRequested,
            ),
          ),
        ),
        Semantics(
          container: true,
          sortKey: const OrdinalSortKey(1),
          child: Padding(
            // Доступная панели область — над клавиатурой и под строкой
            // состояния.
            padding: EdgeInsets.only(
              top: media.padding.top,
              bottom: media.viewInsets.bottom,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: animation.drive(
                  Tween(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: Material(
                    key: const ValueKey('intention-creation-sheet'),
                    color: colors.surfaceContainerLow,
                    elevation: 1,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    // Клавиатура и строка состояния уже учтены положением
                    // панели; внутри остаётся только нижний безопасный отступ.
                    child: MediaQuery(
                      data: media
                          .removePadding(removeTop: true)
                          .removeViewInsets(removeBottom: true),
                      child: SafeArea(
                        top: false,
                        child: NotificationListener<ScrollMetricsNotification>(
                          onNotification: _handleScrollMetrics,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleScroll,
                            child: _SheetLayout(
                              visibleContextExtent: _visibleContextExtent,
                              minVisibleContextExtent: _minVisibleContextExtent,
                              topBar: Semantics(
                                container: true,
                                sortKey: const OrdinalSortKey(0),
                                child: _TopBar(
                                  closeLabel: widget.closeLabel,
                                  onClose: widget.onCloseRequested,
                                  onDragStart: _startDrag,
                                  onDragUpdate: _updateDrag,
                                  onDragEnd: _endDrag,
                                ),
                              ),
                              body: Semantics(
                                container: true,
                                sortKey: const OrdinalSortKey(1),
                                child: _FieldsScaffold(
                                  child: SingleChildScrollView(
                                    key: const ValueKey(
                                      'intention-creation-sheet-fields',
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [widget.header, widget.fields],
                                    ),
                                  ),
                                ),
                              ),
                              status: switch (widget.status) {
                                final status? => Semantics(
                                  container: true,
                                  sortKey: const OrdinalSortKey(2),
                                  child: SingleChildScrollView(
                                    key: const ValueKey(
                                      'intention-creation-sheet-status',
                                    ),
                                    primary: false,
                                    child: status,
                                  ),
                                ),
                                null => null,
                              },
                              // Прокручивается, только если сама не помещается в
                              // тесную доступную область, и не переполняет панель.
                              footer: Semantics(
                                container: true,
                                sortKey: const OrdinalSortKey(3),
                                child: SingleChildScrollView(
                                  primary: false,
                                  child: widget.footer,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Закреплённая верхняя полоса: ручка для свайпа и доступная без жеста
/// кнопка закрытия.
final class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.closeLabel,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final String closeLabel;
  final VoidCallback onClose;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Нажатия и свайпы полосы не считаются нажатием вне поля ввода:
    // взаимодействие с ручкой сохраняет фокус и клавиатуру.
    return TextFieldTapRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Свайп по ручке — дополнительный способ: те же действия экранному
        // диктору даёт кнопка закрытия, поэтому полоса не выдаёт себя
        // прокручиваемой.
        excludeFromSemantics: true,
        onVerticalDragStart: onDragStart,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                key: const ValueKey('intention-creation-sheet-handle'),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  key: const ValueKey('intention-editor-close'),
                  tooltip: closeLabel,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Собственный `Scaffold` панели вокруг её прокручиваемых полей.
///
/// Через него панель участвует в общем `ScaffoldMessenger` приложения:
/// сообщение общей поверхности появляется поверх полей у их нижнего края,
/// не перекрывая закреплённое сообщение и основные действия.
/// Собственного messenger у панели нет.
///
/// `Scaffold` занимает всю данную ему высоту, поэтому при ограничении только
/// сверху область, как и сами поля, следует за высотой полей.
final class _FieldsScaffold extends StatefulWidget {
  const _FieldsScaffold({required this.child});

  /// Прокручиваемые поля панели.
  final Widget child;

  @override
  State<_FieldsScaffold> createState() => _FieldsScaffoldState();
}

final class _FieldsScaffoldState extends State<_FieldsScaffold> {
  final _fields = _FieldsExtent();

  @override
  Widget build(BuildContext context) => _FieldsFrame(
    fields: _fields,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      // Клавиатуру и безопасные отступы уже учла раскладка панели.
      resizeToAvoidBottomInset: false,
      body: _FieldsProbe(fields: _fields, child: widget.child),
    ),
  );
}

/// Высота полей при их последней раскладке внутри `Scaffold`.
final class _FieldsExtent {
  var height = 0.0;
}

/// Запоминает высоту, которую заняли поля в теле `Scaffold`.
final class _FieldsProbe extends SingleChildRenderObjectWidget {
  const _FieldsProbe({required this.fields, required super.child});

  final _FieldsExtent fields;

  @override
  _RenderFieldsProbe createRenderObject(BuildContext context) =>
      _RenderFieldsProbe(fields);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFieldsProbe renderObject,
  ) => renderObject.fields = fields;
}

final class _RenderFieldsProbe extends RenderProxyBox {
  _RenderFieldsProbe(this.fields);

  _FieldsExtent fields;

  @override
  void performLayout() {
    super.performLayout();
    fields.height = size.height;
  }
}

/// Ограничивает `Scaffold` полей высотой самих полей, когда высота задана
/// только сверху.
///
/// Сначала `Scaffold` раскладывается во всю доступную высоту, и тело
/// получает поля по их высоте; затем — повторно в высоту полей. Оба
/// ограничения нестрогие, поэтому рост и уменьшение полей снова доходят до
/// раскладки панели.
final class _FieldsFrame extends SingleChildRenderObjectWidget {
  const _FieldsFrame({required this.fields, required super.child});

  final _FieldsExtent fields;

  @override
  _RenderFieldsFrame createRenderObject(BuildContext context) =>
      _RenderFieldsFrame(fields);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFieldsFrame renderObject,
  ) => renderObject.fields = fields;
}

final class _RenderFieldsFrame extends RenderProxyBox {
  _RenderFieldsFrame(this._fields);

  _FieldsExtent _fields;

  set fields(_FieldsExtent value) {
    if (identical(value, _fields)) {
      return;
    }
    _fields = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Высота области полей зависит от их раскладки.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    final scaffold = child!;
    scaffold.layout(constraints, parentUsesSize: true);
    if (!constraints.hasTightHeight) {
      final height = constraints.constrainHeight(_fields.height);
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

enum _SheetSlot { topBar, body, status, footer }

/// Раскладка панели: закреплённые верхняя полоса, сообщение и нижняя часть и
/// прокручиваемые между ними поля.
///
/// Поля резервируют место до закреплённых частей. Если верхняя полоса и
/// нижняя часть не помещаются вместе с полями, они встают рядом сверху;
/// длинные действия прокручиваются внутри своей области. Высота полей
/// следует за содержимым в пределах доступной высоты за вычетом
/// [visibleContextExtent].
/// Ограничение высоты сверху сохраняет рост по содержимому:
/// https://api.flutter.dev/flutter/rendering/BoxConstraints-class.html
///
/// Если закреплённые части вместе с наименьшей видимой областью полей не
/// помещаются в компактное ограничение, видимый участок страницы
/// уменьшается ради них, но не меньше чем до [minVisibleContextExtent]:
/// основное действие и закрытие остаются доступными, а поля —
/// видимыми и прокручиваемыми, пока высоты хватает хотя бы на часть из них.
///
/// Сообщение получает свою высоту, пока полям остаётся нужное им место; при
/// нехватке полям остаётся не меньше половины места, а сообщение
/// прокручивается в остальном.
final class _SheetLayout
    extends SlottedMultiChildRenderObjectWidget<_SheetSlot, RenderBox> {
  const _SheetLayout({
    required this.visibleContextExtent,
    required this.minVisibleContextExtent,
    required this.topBar,
    required this.body,
    required this.status,
    required this.footer,
  });

  final double visibleContextExtent;
  final double minVisibleContextExtent;
  final Widget topBar;
  final Widget body;
  final Widget? status;
  final Widget footer;

  @override
  Iterable<_SheetSlot> get slots => _SheetSlot.values;

  @override
  Widget? childForSlot(_SheetSlot slot) => switch (slot) {
    _SheetSlot.topBar => topBar,
    _SheetSlot.body => body,
    _SheetSlot.status => status,
    _SheetSlot.footer => footer,
  };

  @override
  _RenderSheetLayout createRenderObject(BuildContext context) =>
      _RenderSheetLayout(
        visibleContextExtent: visibleContextExtent,
        minVisibleContextExtent: minVisibleContextExtent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetLayout renderObject,
  ) {
    renderObject
      ..visibleContextExtent = visibleContextExtent
      ..minVisibleContextExtent = minVisibleContextExtent;
  }
}

final class _RenderSheetLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<_SheetSlot, RenderBox> {
  _RenderSheetLayout({
    required this._visibleContextExtent,
    required this._minVisibleContextExtent,
  });

  double _visibleContextExtent;

  set visibleContextExtent(double value) {
    if (value == _visibleContextExtent) {
      return;
    }
    _visibleContextExtent = value;
    markNeedsLayout();
  }

  double _minVisibleContextExtent;

  set minVisibleContextExtent(double value) {
    if (value == _minVisibleContextExtent) {
      return;
    }
    _minVisibleContextExtent = value;
    markNeedsLayout();
  }

  /// Наименьшая высота полей, которую компактная панель оставляет видимой,
  /// уменьшая ради неё видимый участок страницы: одна цель нажатия.
  static const _minBodyExtent = kMinInteractiveDimension;

  /// Ручка шириной 32 и отдельная цель закрытия в общей полосе действий.
  static const _actionsTopBarWidth = 128.0;

  RenderBox get _topBar => childForSlot(_SheetSlot.topBar)!;

  RenderBox get _body => childForSlot(_SheetSlot.body)!;

  RenderBox? get _status => childForSlot(_SheetSlot.status);

  RenderBox get _footer => childForSlot(_SheetSlot.footer)!;

  /// Порядок обхода совпадает с расположением сверху вниз.
  @override
  Iterable<RenderBox> get children => [
    for (final slot in _SheetSlot.values) ?childForSlot(slot),
  ];

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Компактная высота панели зависит от раскладки полей.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedHeight,
      'Панели нужна ограниченная доступная высота.',
    );
    final width = constraints.maxWidth;
    final available = constraints.maxHeight;
    var topHeight = _layoutChild(_topBar, width, maxHeight: available);
    var footerHeight = _layoutChild(
      _footer,
      width,
      maxHeight: math.max(0, available - topHeight),
    );
    // Наименьшая видимая область полей: без неё над тесной клавиатурой
    // закреплённые части забирали бы всю компактную высоту, и поля исчезали
    // бы и для касания, и для экранного диктора.
    final minBodyHeight = _layoutChild(_body, width, maxHeight: _minBodyExtent);
    final limit = math.max(
      0.0,
      math.max(
        available - _visibleContextExtent,
        math.min(
          topHeight + footerHeight + minBodyHeight,
          available - _minVisibleContextExtent,
        ),
      ),
    );
    final actionsShareRow = topHeight + footerHeight + minBodyHeight > limit;
    // Ширина сохраняет отдельные цели ручки и закрытия в верхней полосе.
    final topWidth = actionsShareRow
        ? math.min(_actionsTopBarWidth, width / 2)
        : width;
    final footerWidth = actionsShareRow ? width - topWidth : width;
    if (actionsShareRow) {
      final actionsLimit = math.max(0.0, limit - minBodyHeight);
      topHeight = _layoutChild(_topBar, topWidth, maxHeight: actionsLimit);
      footerHeight = _layoutChild(
        _footer,
        footerWidth,
        maxHeight: actionsLimit,
      );
    }
    final fixedHeight = actionsShareRow
        ? math.max(topHeight, footerHeight)
        : topHeight + footerHeight;
    final bodyTop = actionsShareRow ? fixedHeight : topHeight;
    final status = _status;
    final statusExtent = status?.getMaxIntrinsicHeight(width) ?? 0;
    final space = math.max(0.0, limit - fixedHeight);
    final statusHeight = _statusShare(space, statusExtent, width);
    final bodyHeight = _layoutChild(
      _body,
      width,
      maxHeight: space - statusHeight,
    );
    if (status != null) {
      _layoutChild(
        status,
        width,
        minHeight: statusHeight,
        maxHeight: statusHeight,
      );
      _position(status, bodyTop + bodyHeight);
    }

    _position(_topBar, 0);
    _position(_body, bodyTop);
    _position(
      _footer,
      actionsShareRow ? 0 : topHeight + bodyHeight + statusHeight,
      left: actionsShareRow ? topWidth : 0,
    );
    size = constraints.constrain(
      Size(width, fixedHeight + bodyHeight + statusHeight),
    );
  }

  /// Высота сообщения в месте [space], которое оно делит с полями: полям
  /// остаётся нужное им место, но не больше половины, а сообщению — остальное
  /// в пределах его высоты [statusExtent].
  double _statusShare(double space, double statusExtent, double width) {
    if (statusExtent == 0) {
      return 0;
    }
    final bodyNeed = _layoutChild(_body, width, maxHeight: space / 2);
    return math.min(statusExtent, space - bodyNeed);
  }

  double _layoutChild(
    RenderBox child,
    double width, {
    required double maxHeight,
    double minHeight = 0,
  }) {
    child.layout(
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: minHeight,
        maxHeight: maxHeight,
      ),
      parentUsesSize: true,
    );
    return child.size.height;
  }

  void _position(RenderBox child, double top, {double left = 0}) =>
      (child.parentData! as BoxParentData).offset = Offset(left, top);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children.toList().reversed) {
      final childOffset = (child.parentData! as BoxParentData).offset;
      final isHit = result.addWithPaintOffset(
        offset: childOffset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (isHit) {
        return true;
      }
    }
    return false;
  }
}
