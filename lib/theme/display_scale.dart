import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

/// App-wide Zoom In / Zoom Out & Display Scale controller (saved on device).
/// - All on-screen zoom indicators/buttons are removed so they never block UI
///   or trigger Overlay/Tooltip errors on hover.
/// - Normal mouse wheel scrolling NEVER triggers zoom.
/// - Desktop/Web Zoom shortcuts:
///   • `Ctrl + Mouse Scroll Wheel` (Zoom In / Zoom Out)
///   • `Ctrl + +` / `Ctrl + =` / `Ctrl + Numpad +` (Zoom In)
///   • `Ctrl + -` / `Ctrl + Numpad -` (Zoom Out)
///   • `Ctrl + 0` (Reset to 100%)
/// - Mobile/Tablet Zoom: Two-finger touch pinch-to-zoom.
class DisplayScale {
  DisplayScale._();

  static const String _prefKey = 'psm_display_scale_v1';

  static const List<(double, String)> options = <(double, String)>[
    (0.50, '50% — ખૂબ નાનું (50%)'),
    (0.60, '60% — નાનું (Fit Wide Tables 60%)'),
    (0.70, '70% — નાનું (Zoom Out 70%)'),
    (0.80, '80% — મધ્યમ નાનું (Zoom Out 80%)'),
    (0.90, '90% — સહેજ નાનું (Zoom Out 90%)'),
    (1.00, '100% — સામાન્ય / Normal (Ctrl+0)'),
    (1.10, '110% — મોટું (110%)'),
    (1.25, '125% — વધુ મોટું (125%)'),
    (1.50, '150% — Zoom In 1.5x'),
    (1.75, '175% — Zoom In 1.75x'),
    (2.00, '200% — Zoom In 2x'),
  ];

  static final ValueNotifier<double> notifier = ValueNotifier<double>(1.0);
  static final ValueNotifier<bool> showFloatingZoomBar =
      ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_prefKey);
      if (v != null && v >= 0.5 && v <= 3.0) {
        notifier.value = v;
      }
    } catch (_) {}
  }

  static Future<void> set(double value) async {
    final clamped =
        double.parse(value.clamp(0.50, 2.50).toStringAsFixed(2));
    if ((notifier.value - clamped).abs() < 0.005) return;
    notifier.value = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKey, clamped);
    } catch (_) {}
  }

  static Future<void> zoomIn([double step = 0.10]) =>
      set(notifier.value + step);

  static Future<void> zoomOut([double step = 0.10]) =>
      set(notifier.value - step);

  static Future<void> reset() => set(1.0);

  static Future<void> toggleFloatingBar([bool? value]) async {
    showFloatingZoomBar.value = false;
  }

  /// Zoom indicator button intentionally hidden across all screens;
  /// zoom operates directly via Ctrl+Scroll, Ctrl++, Ctrl+-, Ctrl+0, and touch pinch.
  static Widget menuButton({Color? color}) => const SizedBox.shrink();
}

/// Wraps the entire app to provide:
/// 1. Normal mouse wheel scrolling NEVER zooms (passes straight through to scroll views).
/// 2. `Ctrl + Mouse Scroll Wheel`, `Ctrl + +`, `Ctrl + -`, and `Ctrl + 0` zoom in/out/reset smoothly.
/// 3. Two-finger touch pinch-to-zoom on mobile touch screens.
/// 4. No floating zoom indicator pill (avoids cursor hover issues and Overlay errors).
class MobileZoomViewport extends StatefulWidget {
  const MobileZoomViewport({super.key, required this.child});

  final Widget child;

  @override
  State<MobileZoomViewport> createState() => _MobileZoomViewportState();
}

class _MobileZoomViewportState extends State<MobileZoomViewport> {
  final GlobalKey _childKey = GlobalKey();

  StreamSubscription<html.MessageEvent>? _webMessageSub;
  int _lastZoomStepMs = 0;

  // Track active touch pointers for 2-finger touch pinch only (never mouse wheel)
  final Map<int, Offset> _touchPoints = <int, Offset>{};
  double? _initialPinchDistance;
  double _initialPinchScale = 1.0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (kIsWeb) {
      _webMessageSub = html.window.onMessage.listen((html.MessageEvent event) {
        final data = '${event.data ?? ''}';
        if (data == 'PSM_ZOOM_IN_WHEEL') {
          _applySteppedZoom(0.08);
        } else if (data == 'PSM_ZOOM_OUT_WHEEL') {
          _applySteppedZoom(-0.08);
        } else if (data == 'PSM_ZOOM_IN_KEY') {
          _applySteppedZoom(0.10);
        } else if (data == 'PSM_ZOOM_OUT_KEY') {
          _applySteppedZoom(-0.10);
        } else if (data == 'PSM_ZOOM_RESET_KEY') {
          _lastZoomStepMs = DateTime.now().millisecondsSinceEpoch;
          DisplayScale.reset();
        }
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _webMessageSub?.cancel();
    super.dispose();
  }

  void _applySteppedZoom(double delta) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastZoomStepMs < 35) return;
    _lastZoomStepMs = now;
    DisplayScale.set(DisplayScale.notifier.value + delta);
  }

  bool _isCtrlOrMetaPressed() {
    final hw = HardwareKeyboard.instance;
    final keys = hw.logicalKeysPressed;
    return hw.isControlPressed ||
        hw.isMetaPressed ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.control) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    if (!_isCtrlOrMetaPressed() || HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final logical = event.logicalKey;
    final physical = event.physicalKey;
    final ch = event.character ?? '';

    // Ctrl + '+' or Ctrl + '=' or Ctrl + NumpadAdd -> Zoom In
    if (logical == LogicalKeyboardKey.equal ||
        logical == LogicalKeyboardKey.add ||
        logical == LogicalKeyboardKey.numpadAdd ||
        physical == PhysicalKeyboardKey.equal ||
        physical == PhysicalKeyboardKey.numpadAdd ||
        ch == '+' ||
        ch == '=') {
      _applySteppedZoom(0.10);
      return true;
    }

    // Ctrl + '-' or Ctrl + '_' or Ctrl + NumpadSubtract -> Zoom Out
    if (logical == LogicalKeyboardKey.minus ||
        logical == LogicalKeyboardKey.numpadSubtract ||
        physical == PhysicalKeyboardKey.minus ||
        physical == PhysicalKeyboardKey.numpadSubtract ||
        ch == '-' ||
        ch == '_') {
      _applySteppedZoom(-0.10);
      return true;
    }

    // Ctrl + '0' or Ctrl + Numpad0 -> Reset to 100%
    if (logical == LogicalKeyboardKey.digit0 ||
        logical == LogicalKeyboardKey.numpad0 ||
        physical == PhysicalKeyboardKey.digit0 ||
        physical == PhysicalKeyboardKey.numpad0 ||
        ch == '0') {
      _lastZoomStepMs = DateTime.now().millisecondsSinceEpoch;
      DisplayScale.reset();
      return true;
    }

    return false;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    // 1. In Flutter Web, Ctrl + Mouse Wheel is often translated by the engine
    //    into a PointerScaleEvent!
    if (event is PointerScaleEvent) {
      if ((event.scale - 1.0).abs() < 0.002) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        final scaleEvent = e as PointerScaleEvent;
        final delta = scaleEvent.scale > 1.0 ? 0.08 : -0.08;
        _applySteppedZoom(delta);
      });
      return;
    }

    // 2. On Desktop/Web when PointerScrollEvent fires: ONLY zoom if Ctrl is held!
    if (event is PointerScrollEvent) {
      if (!_isCtrlOrMetaPressed()) {
        // Normal scroll wheel without Ctrl: do nothing, let scroll views scroll!
        return;
      }
      final dy = event.scrollDelta.dy;
      if (dy.abs() < 0.5) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        final scrollEvent = e as PointerScrollEvent;
        final delta = scrollEvent.scrollDelta.dy < 0 ? 0.08 : -0.08;
        _applySteppedZoom(delta);
      });
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPoints[event.pointer] = event.position;
    if (_touchPoints.length == 2) {
      final pts = _touchPoints.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      if (dist > 12.0) {
        _initialPinchDistance = dist;
        _initialPinchScale = DisplayScale.notifier.value;
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (!_touchPoints.containsKey(event.pointer)) return;
    _touchPoints[event.pointer] = event.position;
    if (_touchPoints.length == 2 && _initialPinchDistance != null) {
      final pts = _touchPoints.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      if (dist > 12.0 && _initialPinchDistance! > 12.0) {
        final ratio = dist / _initialPinchDistance!;
        final nextScale = (_initialPinchScale * ratio).clamp(0.50, 2.50);
        if ((nextScale - DisplayScale.notifier.value).abs() >= 0.02) {
          DisplayScale.notifier.value =
              double.parse(nextScale.toStringAsFixed(2));
        }
      }
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    if (_touchPoints.remove(event.pointer) != null) {
      if (_touchPoints.length < 2 && _initialPinchDistance != null) {
        _initialPinchDistance = null;
        DisplayScale.set(DisplayScale.notifier.value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;

    return ValueListenableBuilder<double>(
      valueListenable: DisplayScale.notifier,
      builder: (context, scale, _) {
        final effectiveScale = scale.clamp(0.50, 2.50);
        Widget content = KeyedSubtree(
          key: _childKey,
          child: widget.child,
        );

        if (screenSize.width > 0 && screenSize.height > 0) {
          final virtualW = screenSize.width / effectiveScale;
          final virtualH = screenSize.height / effectiveScale;
          final adjustedPadding = mq.padding / effectiveScale;
          final adjustedViewInsets = mq.viewInsets / effectiveScale;
          final adjustedViewPadding = mq.viewPadding / effectiveScale;

          content = SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: virtualW,
                height: virtualH,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(virtualW, virtualH),
                    padding: adjustedPadding,
                    viewInsets: adjustedViewInsets,
                    viewPadding: adjustedViewPadding,
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: content,
                ),
              ),
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _handlePointerSignal,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUpOrCancel,
          onPointerCancel: _handlePointerUpOrCancel,
          child: content,
        );
      },
    );
  }
}
