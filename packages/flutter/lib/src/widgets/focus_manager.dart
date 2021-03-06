// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A leaf node in the focus tree that can receive focus.
///
/// The focus tree keeps track of which widget is the user's current focus. The
/// focused widget often listens for keyboard events.
///
/// To request focus, find the [FocusScopeNode] for the current [BuildContext]
/// and call the [FocusScopeNode.requestFocus] method:
///
/// ```dart
/// FocusScope.of(context).requestFocus(focusNode);
/// ```
///
/// If your widget requests focus, be sure to call
/// `FocusScope.of(context).reparentIfNeeded(focusNode);` in your `build`
/// method to reparent your [FocusNode] if your widget moves from one
/// location in the tree to another.
///
/// See also:
///
///  * [FocusScopeNode], which is an interior node in the focus tree.
///  * [FocusScope.of], which provides the [FocusScopeNode] for a given
///    [BuildContext].
class FocusNode extends ChangeNotifier {
  FocusScopeNode _parent;
  FocusManager _manager;

  /// Whether this node has the overall focus.
  ///
  /// A [FocusNode] has the overall focus when the node is focused in its
  /// parent [FocusScopeNode] and [FocusScopeNode.isFirstFocus] is true for
  /// that scope and all its ancestor scopes.
  ///
  /// To request focus, find the [FocusScopeNode] for the current [BuildContext]
  /// and call the [FocusScopeNode.requestFocus] method:
  ///
  /// ```dart
  /// FocusScope.of(context).requestFocus(focusNode);
  /// ```
  ///
  /// This object notifies its listeners whenever this value changes.
  bool get hasFocus => _manager?._currentFocus == this;

  /// Cancels any outstanding requests for focus.
  ///
  /// This method is safe to call regardless of whether this node has ever
  /// requested focus.
  void unfocus() {
    _parent?._resignFocus(this);
    assert(_parent == null);
    assert(_manager == null);
  }

  @override
  void dispose() {
    _manager?._willDisposeFocusNode(this);
    _parent?._resignFocus(this);
    assert(_parent == null);
    assert(_manager == null);
    super.dispose();
  }

  void _notify() {
    notifyListeners();
  }

  @override
  String toString() => '$runtimeType#$hashCode${hasFocus ? '(FOCUSED)' : ''}';
}

/// An interior node in the focus tree.
///
/// The focus tree keeps track of which widget is the user's current focus. The
/// focused widget often listens for keyboard events.
///
/// The interior nodes in the focus tree cannot themselves be focused but
/// instead remember previous focus states. A scope is currently active in its
/// parent whenever [isFirstFocus] is true. If that scope is detached from its
/// parent, its previous sibling becomes the parent's first focus.
///
/// A [FocusNode] has the overall focus when the node is focused in its
/// parent [FocusScopeNode] and [FocusScopeNode.isFirstFocus] is true for
/// that scope and all its ancestor scopes.
///
/// See also:
///
///  * [FocusNode], which is a leaf node in the focus tree that can receive
///    focus.
///  * [FocusScope.of], which provides the [FocusScopeNode] for a given
///    [BuildContext].
///  * [FocusScope], which is a widget that associates a [FocusScopeNode] with
///    its location in the tree.
class FocusScopeNode extends Object with TreeDiagnosticsMixin {
  FocusManager _manager;
  FocusScopeNode _parent;

  FocusScopeNode _nextSibling;
  FocusScopeNode _previousSibling;

  FocusScopeNode _firstChild;
  FocusScopeNode _lastChild;

  FocusNode _focus;

  /// Whether this scope is currently active in its parent scope.
  bool get isFirstFocus => _parent == null || _parent._firstChild == this;

  void _prepend(FocusScopeNode child) {
    assert(child != this);
    assert(child != _firstChild);
    assert(child != _lastChild);
    assert(child._parent == null);
    assert(child._manager == null);
    assert(child._nextSibling == null);
    assert(child._previousSibling == null);
    assert(() {
      FocusScopeNode node = this;
      while (node._parent != null)
        node = node._parent;
      assert(node != child); // indicates we are about to create a cycle
      return true;
    });
    child._parent = this;
    child._nextSibling = _firstChild;
    if (_firstChild != null)
      _firstChild._previousSibling = child;
    _firstChild = child;
    _lastChild ??= child;
    child._updateManager(_manager);
  }

  void _updateManager(FocusManager manager) {
    void update(FocusScopeNode child) {
      if (child._manager == manager)
        return;
      child._manager = manager;
      // We don't proactively null out the manager for FocusNodes because the
      // manager holds the currently active focus node until the end of the
      // microtask, even if that node is detached from the focus tree.
      if (manager != null)
        child._focus?._manager = manager;
      child._visitChildren(update);
    }

    update(this);
  }

  void _visitChildren(void visitor(FocusScopeNode child)) {
    FocusScopeNode child = _firstChild;
    while (child != null) {
      visitor(child);
      child = child._nextSibling;
    }
  }

  bool _debugUltimatePreviousSiblingOf(FocusScopeNode child, { FocusScopeNode equals }) {
    while (child._previousSibling != null) {
      assert(child._previousSibling != child);
      child = child._previousSibling;
    }
    return child == equals;
  }

  bool _debugUltimateNextSiblingOf(FocusScopeNode child, { FocusScopeNode equals }) {
    while (child._nextSibling != null) {
      assert(child._nextSibling != child);
      child = child._nextSibling;
    }
    return child == equals;
  }

  void _remove(FocusScopeNode child) {
    assert(child._parent == this);
    assert(child._manager == _manager);
    assert(_debugUltimatePreviousSiblingOf(child, equals: _firstChild));
    assert(_debugUltimateNextSiblingOf(child, equals: _lastChild));
    if (child._previousSibling == null) {
      assert(_firstChild == child);
      _firstChild = child._nextSibling;
    } else {
      child._previousSibling._nextSibling = child._nextSibling;
    }
    if (child._nextSibling == null) {
      assert(_lastChild == child);
      _lastChild = child._previousSibling;
    } else {
      child._nextSibling._previousSibling = child._previousSibling;
    }
    child._previousSibling = null;
    child._nextSibling = null;
    child._parent = null;
    child._updateManager(null);
  }

  void _didChangeFocusChain() {
    if (isFirstFocus)
      _manager?._markNeedsUpdate();
  }

  /// Requests that the given node becomes the focus for this scope.
  ///
  /// If the given node is currently focused in another scope, the node will
  /// first be unfocused in that scope.
  ///
  /// The node will receive the overall focus if this [isFirstFocus] is true
  /// in this scope and all its ancestor scopes. The node is notified that it
  /// has received the overall focus in a microtask.
  void requestFocus(FocusNode node) {
    assert(node != null);
    if (_focus == node)
      return;
    assert(node._parent == null);
    _focus?.unfocus();
    assert(_focus == null);
    _focus = node;
    _focus._parent = this;
    _focus._manager = _manager;
    _didChangeFocusChain();
  }

  /// If this scope lacks a focus, request that the given node becomes the
  /// focus.
  ///
  /// Useful for widgets that wish to grab the focus if no other widget already
  /// has the focus.
  ///
  /// The node is notified that it has received the overall focus in a
  /// microtask.
  void autofocus(FocusNode node) {
    assert(node != null);
    if (_focus == null)
      requestFocus(node);
  }

  /// Adopts the given node if it is focused in another scope.
  ///
  /// A widget that requests that a node is focused should call this method
  /// during its `build` method in case the widget is moved from one location
  /// in the tree to another location that has a different focus scope.
  void reparentIfNeeded(FocusNode node) {
    assert(node != null);
    if (node._parent == null || node._parent == this)
      return;
    node.unfocus();
    assert(node._parent == null);
    autofocus(node);
  }

  void _resignFocus(FocusNode node) {
    assert(node != null);
    if (_focus != node)
      return;
    _focus._parent = null;
    _focus._manager = null;
    _focus = null;
    _didChangeFocusChain();
  }

  /// Makes the given child the first focus of this scope.
  ///
  /// If the child has another parent scope, the child is first removed from
  /// that scope. After this method returns [isFirstFocus] will be true for
  /// the child.
  void setFirstFocus(FocusScopeNode child) {
    assert(child != null);
    assert(child._parent == null || child._parent == this);
    if (_firstChild == child)
      return;
    child.detach();
    _prepend(child);
    assert(child._parent == this);
    _didChangeFocusChain();
  }

  /// Adopts the given scope if it is the first focus of another scope.
  ///
  /// A widget that sets a scope as the first focus of another scope should
  /// call this method during its `build` method in case the widget is moved
  /// from one location in the tree to another location that has a different
  /// focus scope.
  ///
  /// If the given scope is not the first focus of its old parent, the scope
  /// is simply detached from its old parent.
  void reparentScopeIfNeeded(FocusScopeNode child) {
    assert(child != null);
    if (child._parent == null || child._parent == this)
      return;
    if (child.isFirstFocus)
      setFirstFocus(child);
    else
      child.detach();
  }

  /// Remove this scope from its parent child list.
  ///
  /// This method is safe to call even if this scope does not have a parent.
  ///
  /// A widget that sets a scope as the first focus of another scope should
  /// call this method during [State.dispose] to avoid leaving dangling
  /// children in their parent scope.
  void detach() {
    _didChangeFocusChain();
    _parent?._remove(this);
    assert(_parent == null);
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (_focus != null)
      description.add('focus: $_focus');
  }

  @override
  String debugDescribeChildren(String prefix) {
    final StringBuffer buffer = new StringBuffer();
    if (_firstChild != null) {
      FocusScopeNode child = _firstChild;
      int count = 1;
      while (child != _lastChild) {
        buffer.write(child.toStringDeep("$prefix \u251C\u2500child $count: ", "$prefix \u2502"));
        count += 1;
        child = child._nextSibling;
      }
      if (child != null) {
        assert(child == _lastChild);
        buffer.write(child.toStringDeep("$prefix \u2514\u2500child $count: ", "$prefix  "));
      }
    }
    return buffer.toString();
  }
}

/// Manages the focus tree.
///
/// The focus tree keeps track of which widget is the user's current focus. The
/// focused widget often listens for keyboard events.
///
/// The focus manager is responsible for holding the [FocusScopeNode] that is
/// the root of the focus tree and tracking which [FocusNode] has the overall
/// focus.
///
/// The [FocusManager] is held by the [WidgetBinding] as
/// [WidgetBinding.focusManager]. The [FocusManager] is rarely accessed
/// directly. Instead, to find the [FocusScopeNode] for a given [BuildContext],
/// use [FocusScope.of].
///
/// See also:
///
///  * [FocusNode], which is a leaf node in the focus tree that can receive
///    focus.
///  * [FocusScopeNode], which is an interior node in the focus tree.
///  * [FocusScope.of], which provides the [FocusScopeNode] for a given
///    [BuildContext].
class FocusManager {
  /// Creates an object that manages the focus tree.
  ///
  /// This constructor is rarely called directly. To access the [FocusManager],
  /// consider using [WidgetBinding.focusManager] instead.
  FocusManager() {
    rootScope._manager = this;
    assert(rootScope._firstChild == null);
    assert(rootScope._lastChild == null);
  }

  /// The root [FocusScopeNode] in the focus tree.
  ///
  /// This field is rarely used direction. Instead, to find the
  /// [FocusScopeNode] for a given [BuildContext], use [FocusScope.of].
  final FocusScopeNode rootScope = new FocusScopeNode();

  FocusNode _currentFocus;

  void _willDisposeFocusNode(FocusNode node) {
    assert(node != null);
    if (_currentFocus == node)
      _currentFocus = null;
  }

  bool _haveScheduledUpdate = false;
  void _markNeedsUpdate() {
    if (_haveScheduledUpdate)
      return;
    _haveScheduledUpdate = true;
    scheduleMicrotask(_update);
  }

  FocusNode _findNextFocus() {
    FocusScopeNode scope = rootScope;
    while (scope._firstChild != null)
      scope = scope._firstChild;
    return scope._focus;
  }

  void _update() {
    _haveScheduledUpdate = false;
    final FocusNode nextFocus = _findNextFocus();
    if (_currentFocus == nextFocus)
      return;
    final FocusNode previousFocus = _currentFocus;
    _currentFocus = nextFocus;
    previousFocus?._notify();
    _currentFocus?._notify();
  }

  @override
  String toString() {
    final String status = _haveScheduledUpdate ? ' UPDATE SCHEDULED' : '';
    final String indent = '  ';
    return '$runtimeType#$hashCode$status\n'
      '${indent}currentFocus: $_currentFocus\n'
      '${rootScope.toStringDeep(indent, indent)}';
  }
}
