import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const _stepCounterMethodChannel = MethodChannel('step_counter/methods');

/// Ensure that we have ACTIVITY_RECOGNITION on Android
Future<bool> ensureActivityRecognitionPermission() async {
  if (kIsWeb || !Platform.isAndroid) {
    return true;
  }

  final status = await Permission.activityRecognition.status;
  if (status.isGranted) {
    // Ensure that tracking service works
    try {
      await _stepCounterMethodChannel
          .invokeMethod('startTrackingService');
    } catch (_) {}
    return true;
  }

  final result = await Permission.activityRecognition.request();
  final granted = result.isGranted;

    try {
      await _stepCounterMethodChannel
          .invokeMethod('startTrackingService');
    } catch (_) {
      // ignore
    }

  return granted;
}
