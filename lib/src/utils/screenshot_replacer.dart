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
    // ignore: discarded_futures
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
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

  Future<void> _capture() async {
    if (!mounted) return;

    final ui.Image image;
    try {
      final boundary = _globalKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null || boundary.debugNeedsPaint) {
        if (_retries >= ScreenshotReplacer.maxRetries) {
          // The child is never going to be painted, so there will be no
          // screenshot: report completion and stop, instead of rescheduling
          // (and requesting frames) forever.
          _reportCompleted();
          return;
        }
        _retries++;

        // The boundary is not attached or not painted yet, which may happen if
        // the child is not ready by the end of the frame. Retry on the next
        // frame *without* reporting completion: the screenshot does not exist
        // yet, so whoever waits for it must keep waiting.
        WidgetsBinding.instance
          ..scheduleFrame()
          ..addPostFrameCallback((_) => _capture());
        return;
      }

      image = await boundary.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
    } on Object {
      // There will be no screenshot at all, so nobody may be left waiting for
      // one. Note that this also covers `debugNeedsPaint` itself, which throws
      // when asserts are disabled.
      _reportCompleted();
      rethrow;
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
