// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'material.dart';
import 'theme.dart';

// Used for Android and Fuchsia.
class _MountainViewPageTransition extends AnimatedWidget {
  static final FractionalOffsetTween _kTween = new FractionalOffsetTween(
    begin: FractionalOffset.bottomLeft,
    end: FractionalOffset.topLeft
  );

  _MountainViewPageTransition({
    Key key,
    Animation<double> animation,
    this.child
  }) : super(
    key: key,
    animation: _kTween.animate(new CurvedAnimation(
      parent: animation, // The route's linear 0.0 - 1.0 animation.
      curve: Curves.fastOutSlowIn
    )
  ));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // TODO(ianh): tell the transform to be un-transformed for hit testing
    return new SlideTransition(
      position: animation,
      child: child
    );
  }
}

// Used for iOS.
class _CupertinoPageTransition extends AnimatedWidget {
  static final FractionalOffsetTween _kTween = new FractionalOffsetTween(
    begin: FractionalOffset.topRight,
    end: -FractionalOffset.topRight
  );

  _CupertinoPageTransition({
    Key key,
    Animation<double> animation,
    this.child
  }) : super(
    key: key,
    animation: _kTween.animate(new CurvedAnimation(
      parent: animation,
      curve: new _CupertinoTransitionCurve()
    )
  ));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // TODO(ianh): tell the transform to be un-transformed for hit testing
    // but not while being controlled by a gesture.
    return new SlideTransition(
      position: animation,
      child: new Material(
        elevation: 6,
        child: child
      )
    );
  }
}

class AnimationMean extends CompoundAnimation<double> {
  AnimationMean({
    Animation<double> left,
    Animation<double> right,
  }) : super(first: left, next: right);

  @override
  double get value => (first.value + next.value) / 2.0;
}

// Custom curve for iOS page transitions. The halfway point is when the page
// is fully on-screen. 0.0 is fully off-screen to the right. 1.0 is off-screen
// to the left.
class _CupertinoTransitionCurve extends Curve {
  _CupertinoTransitionCurve();

  @override
  double transform(double t) {
    if (t > 0.5)
      return (t - 0.5) / 3.0 + 0.5;
    return t;
  }
}

// This class responds to drag gestures to control the route's transition
// animation progress. Used for iOS back gesture.
class _CupertinoBackGestureController extends NavigationGestureController {
  _CupertinoBackGestureController({
    NavigatorState navigator,
    this.controller,
    this.onDisposed,
  }) : super(navigator);

  AnimationController controller;
  VoidCallback onDisposed;

  @override
  void dispose() {
    super.dispose();
    onDisposed();
    controller.removeStatusListener(handleStatusChanged);
    controller = null;
  }

  @override
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  @override
  void dragEnd() {
    if (controller.value <= 0.5) {
      navigator.pop();
    } else {
      controller.forward();
    }
    // Don't end the gesture until the transition completes.
    handleStatusChanged(controller.status);
    controller?.addStatusListener(handleStatusChanged);
  }

  void handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed || status == AnimationStatus.completed)
      dispose();
  }
}

/// A modal route that replaces the entire screen with a material design transition.
///
/// The entrance transition for the page slides the page upwards and fades it
/// in. The exit transition is the same, but in reverse.
///
/// [MaterialApp] creates material page routes for entries in the
/// [MaterialApp.routes] map.
///
/// By default, when a modal route is replaced by another, the previous route
/// remains in memory. To free all the resources when this is not necessary, set
/// [maintainState] to false.
class MaterialPageRoute<T> extends PageRoute<T> {
  /// Creates a page route for use in a material design app.
  MaterialPageRoute({
    this.builder,
    Completer<T> completer,
    RouteSettings settings: const RouteSettings(),
    this.maintainState: true,
  }) : super(completer: completer, settings: settings) {
    assert(builder != null);
    assert(opaque);
  }

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Color get barrierColor => null;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> nextRoute) {
    return nextRoute is MaterialPageRoute<dynamic>;
  }

  @override
  void dispose() {
    super.dispose();
    backGestureController?.dispose();
  }

  _CupertinoBackGestureController backGestureController;

  @override
  NavigationGestureController startPopGesture(NavigatorState navigator) {
    assert(backGestureController == null);
    backGestureController = new _CupertinoBackGestureController(
      navigator: navigator,
      controller: controller,
      onDisposed: () { backGestureController = null; }
    );
    return backGestureController;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> forwardAnimation) {
    Widget result = builder(context);
    assert(() {
      if (result == null) {
        throw new FlutterError(
          'The builder for route "${settings.name}" returned null.\n'
          'Route builders must never return null.'
        );
      }
      return true;
    });
    return result;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> forwardAnimation, Widget child) {
    // TODO(mpcomplete): This hack prevents the previousRoute from animating
    // when we pop(). Remove once we fix this bug:
    // https://github.com/flutter/flutter/issues/5577
    if (!Navigator.of(context).userGestureInProgress)
      forwardAnimation = kAlwaysDismissedAnimation;

    ThemeData theme = Theme.of(context);
    switch (theme.platform) {
      case TargetPlatform.fuchsia:
      case TargetPlatform.android:
        return new _MountainViewPageTransition(
          animation: animation,
          child: child
        );
      case TargetPlatform.iOS:
        return new _CupertinoPageTransition(
          animation: new AnimationMean(left: animation, right: forwardAnimation),
          child: child
        );
    }

    return null;
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}
