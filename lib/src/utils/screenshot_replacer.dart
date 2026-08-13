import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A widget that renders its [child] once, captures a screenshot of it,
/// and then replaces the child with the captured image.
class ScreenshotReplacer extends StatefulWidget {
  /// The number of extra frames the capture waits for the [child] to be
  /// painted before giving up.
  ///
  /// A child that is built but never painted -- an `Offstage` subtree, or the
  /// unselected branch of an `IndexedStack`, for example -- can never be
  /// captured, so the retries have to be bounded: on the last attempt
  /// [onCompleted] is called anyway, leaving [child] in place instead of
  /// keeping the caller waiting for a screenshot forever.
  static const maxRetries = 5;

  /// Called once the screenshot is no longer pending.
  ///
  /// Called exactly once per state: either after [child] has been replaced with
  /// the captured image, or after the capture has definitively failed (see
  /// [maxRetries]), or when this widget is removed from the tree.
  final void Function() onCompleted;

  /// The widget to be screenshot.
  final Widget child;

  /// Creates a [ScreenshotReplacer].
  const ScreenshotReplacer({
    super.key,
    required this.onCompleted,
    required this.child,
  });

  @override
  State<ScreenshotReplacer> createState() => _ScreenshotReplacerState();
}

class _ScreenshotReplacerState extends State<ScreenshotReplacer> {
  final GlobalKey _globalKey = GlobalKey();
  ui.Image? _image;
  bool _isCaptured = false;
  bool _isCompletionReported = false;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_capture()));
  }

  @override
  void dispose() {
    // The last chance to report completion: no further capture attempt can
    // happen once the state is gone.
    _reportCompleted();
    // The state owns this handle: [RawImage] clones the image for its render
    // object and never disposes of the original.
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// Reports that the screenshot is no longer pending.
  ///
  /// Reports at most once, so a single [ScreenshotReplacer.onCompleted] call is
  /// guaranteed regardless of which path finished the capture.
  void _reportCompleted() {
    if (_isCompletionReported) return;
    _isCompletionReported = true;

    widget.onCompleted();
  }

  /// Schedules one more capture attempt on the next frame, or gives up once
  /// [ScreenshotReplacer.maxRetries] attempts have been spent.
  ///
  /// Retrying does not report completion: the screenshot does not exist yet,
  /// so whoever waits for it must keep waiting. Giving up does, so that the
  /// caller is never left waiting forever; an [error] that survived every
  /// retry is reported once, non-fatally — the screenshot is an embellishment,
  /// and failing to take it must not bring the application down.
  void _retryOrGiveUp({Object? error, StackTrace? stackTrace}) {
    if (_retries >= ScreenshotReplacer.maxRetries) {
      if (error != null) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
            context: ErrorDescription('while capturing a screenshot'),
          ),
        );
      }
      _reportCompleted();

      return;
    }
    _retries++;

    WidgetsBinding.instance
      ..scheduleFrame()
      ..addPostFrameCallback((_) => unawaited(_capture()));
  }

  Future<void> _capture() async {
    if (!mounted) return;

    final boundary =
        _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    // [RenderObject.debugNeedsPaint] only holds a value while asserts are
    // enabled, so this pre-check exists in debug builds alone. In release and
    // profile builds a boundary that has not been painted yet is detected by
    // [RenderRepaintBoundary.toImage] failing below, and is retried the same
    // way.
    var needsPaint = false;
    assert(() {
      needsPaint = boundary?.debugNeedsPaint ?? false;

      return true;
    }());

    if (boundary == null || needsPaint) {
      // The boundary is not attached or not painted yet, which may happen if
      // the child is not ready by the end of the frame.
      _retryOrGiveUp();

      return;
    }

    final ui.Image image;
    try {
      image = await boundary.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
    } on Object catch (error, stackTrace) {
      // In release and profile builds this is what a not-yet-painted boundary
      // looks like, so it is retried rather than reported at once.
      _retryOrGiveUp(error: error, stackTrace: stackTrace);

      return;
    }

    if (!mounted) {
      // Disposed of while the image was being rasterized: nothing will ever
      // display it, and [dispose] has already reported completion.
      image.dispose();
      return;
    }

    setState(() {
      _image = image;
      _isCaptured = true;
    });

    _reportCompleted();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCaptured && _image != null) {
      return RawImage(
        image: _image,
        scale: MediaQuery.of(context).devicePixelRatio,
        // This ensures the image respects the parent constraints if needed,
        // though specific sizing behavior might depend on use case.
        // RawImage defaults to the image size.
      );
    }

    return RepaintBoundary(key: _globalKey, child: widget.child);
  }
}
