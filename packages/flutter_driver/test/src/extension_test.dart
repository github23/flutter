// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/scheduler.dart';
import 'package:flutter_driver/src/extension.dart';
import 'package:flutter_driver/src/find.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('waitUntilNoTransientCallbacks', () {
    FlutterDriverExtension extension;
    Map<String, dynamic> result;

    setUp(() {
      result = null;
      extension = new FlutterDriverExtension();
    });

    testWidgets('returns immediately when transient callback queue is empty', (WidgetTester tester) async {
      extension.call(new WaitUntilNoTransientCallbacks().serialize())
          .then<Null>(expectAsync1((Map<String, dynamic> r) {
        result = r;
      }));

      await tester.idle();
      expect(
          result,
          <String, dynamic>{
            'isError': false,
            'response': null,
          },
      );
    });

    testWidgets('waits until no transient callbacks', (WidgetTester tester) async {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        // Intentionally blank. We only care about existence of a callback.
      });

      extension.call(new WaitUntilNoTransientCallbacks().serialize())
          .then<Null>(expectAsync1((Map<String, dynamic> r) {
        result = r;
      }));

      // Nothing should happen until the next frame.
      await tester.idle();
      expect(result, isNull);

      // NOW we should receive the result.
      await tester.pump();
      expect(
          result,
          <String, dynamic>{
            'isError': false,
            'response': null,
          },
      );
    });
  });
}
