import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A widget that renders its [child] once, captures a screenshot of it,
/// and then replaces the child with the captured image.
///
/// {@category utils}
final class ScreenshotReplacer extends StatefulWidget {
  /// The number of extra frames the capture waits for the [child] to be
  /// painted before giving up.
  ///
  /// A child that is built but never painted -- an `Offstage` subtree, or the
  /// unselected branch of an `IndexedStack`, for example -- can never be
  /// captured, so the retries have to be bounded: on the last attempt
  /// [onCompleted] is called anyway, rather than keeping the caller waiting
  /// for a screenshot forever.
  ///
  /// **The child is taken away either way.** Giving up on the picture is not
  /// giving up on replacing the child: what waits on [onCompleted] waits in
  /// order to let go of whatever the child holds, and leaving it standing gave
  /// that caller the report without the thing it was reported for. With no
  /// image to put there, what takes its place is nothing.
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

final class _ScreenshotReplacerState extends State<ScreenshotReplacer> {
  final GlobalKey _globalKey = GlobalKey();
  ui.Image? _image;
  bool _isCaptured = false;
  bool _isCompletionReported = false;
  bool _gaveUp = false;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_capture()));
  }

  @override
  void dispose() {
    // The state owns this handle: [RawImage] clones the image for its render
    // object and never disposes of the original. Released before the
    // application is told anything, so that what this state holds does not
    // depend on what the callback does.
    //
    // The two do not meet today: a capture that produced an image reported
    // completion in the same synchronous step, so when [dispose] is the one to
    // report, [_image] is null. The order costs nothing and does not rely on
    // that staying true.
    _image?.dispose();
    _image = null;
    // The last chance to report completion: no further capture attempt can
    // happen once the state is gone.
    _reportCompleted();
    super.dispose();
  }

  /// Reports that the screenshot is no longer pending.
  ///
  /// Reports at most once, so a single [ScreenshotReplacer.onCompleted] call is
  /// guaranteed regardless of which path finished the capture.
  void _reportCompleted() {
    if (_isCompletionReported) return;
    _isCompletionReported = true;

    try {
      widget.onCompleted();
    } on Object catch (error, stackTrace) {
      // The callback belongs to the application, and every place that calls it
      // is a place nobody is waiting on: the capture runs as an unawaited future
      // in a post-frame callback, and the last resort is `dispose`. A raise left
      // in the first surfaces as an unhandled zone error far from this widget;
      // one left in the second comes out of `State.dispose` and takes the
      // unmount with it. Reported instead, the way the package reports every
      // failure it cannot re-throw -- and non-fatally, because the screenshot is
      // an embellishment.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'scopo',
          context: ErrorDescription(
            'while reporting that a screenshot is no longer pending',
          ),
        ),
      );
    }
  }

  /// Schedules one more capture attempt on the next frame, or gives up once
  /// [ScreenshotReplacer.maxRetries] attempts have been spent.
  ///
  /// Retrying does not report completion: the screenshot does not exist yet,
  /// so whoever waits for it must keep waiting. Giving up does, so that the
  /// caller is never left waiting forever.
  ///
  /// Giving up also takes the child away, which is the half that is not an
  /// embellishment: see [ScreenshotReplacer.maxRetries].
  ///
  /// **Nothing is reported.** An error that survived every retry used to go
  /// to [FlutterError.reportError], and the case it reported was the one this
  /// class documents as ordinary: a subtree that is never painted cannot be
  /// captured. In debug the pre-check above catches that before `toImage` is
  /// ever reached, so the report only ever happened in release — a line in a
  /// crash reporter for a situation the developer could not see happening, and
  /// one that is not a failure of the application at all. What did happen is
  /// said the way it is always said, through [ScreenshotReplacer.onCompleted]
  /// and the absence of a picture.
  void _retryOrGiveUp() {
    if (_retries >= ScreenshotReplacer.maxRetries) {
      // Before the report, so a caller told that the screenshot is no longer
      // pending finds the subtree already on its way out rather than still
      // standing.
      if (mounted) {
        setState(() {
          _gaveUp = true;
        });
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
    // way. There is no release-safe question to ask instead: what `toImage`
    // dereferences is [RenderObject.layer], and that getter is `@protected`.
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
      // ignore: avoid_catching_errors
    } on Object {
      // In release and profile builds this is what a not-yet-painted boundary
      // looks like -- the pre-check above is debug-only -- so it is retried,
      // and if the retries run out it is not reported either: see
      // [_retryOrGiveUp].
      _retryOrGiveUp();

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

    if (_gaveUp) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(key: _globalKey, child: widget.child);
  }
}
