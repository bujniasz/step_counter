import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'step_counter_repository.dart';

class AndroidStepCounterRepository implements StepCounterRepository {
  const AndroidStepCounterRepository();

  static const MethodChannel _methodChannel =
      MethodChannel('step_counter/methods');
  static const EventChannel _eventChannel =
      EventChannel('step_counter/events');

  static int _lastTodaySteps = 0;
  static bool _isListening = false;
  static StreamSubscription<dynamic>? _subscription;
  static final StreamController<int> _stepsController =
    StreamController<int>.broadcast();

  String _dateKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }


  static void _ensureListening() {
    if (_isListening) return;
    _isListening = true;

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is int) {
          _lastTodaySteps = event;
        } else if (event is num) {
          _lastTodaySteps = event.toInt();
        }

        if (!_stepsController.isClosed) {
          _stepsController.add(_lastTodaySteps);
        }
      },
      onError: (error, stack) {
        if (kDebugMode) {
          // only in debug
          print('Step counter event error: $error');
        }
      },
    );
  }

  @override
  Future<int> getStepsForDate(DateTime date) async {
    _ensureListening();

    final now = DateTime.now();
    final isToday = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;

    final dateKey = _dateKey(date);

    if (isToday) {
      try {
        final result =
            await _methodChannel.invokeMethod<int>('getTodaySteps');
        if (result != null) {
          _lastTodaySteps = result;
          return result;
        }
      } catch (e) {
        if (kDebugMode) {
          print('getTodaySteps error: $e');
        }
      }
      // Fallback: last known valeu
      return _lastTodaySteps;
    }

    // other days - read from history
    try {
      final result = await _methodChannel.invokeMethod<int>(
        'getStepsForDate',
        dateKey,
      );
      return result ?? 0;
    } catch (e) {
      if (kDebugMode) {
        print('getStepsForDate error: $e');
      }
      return 0;
    }
  }


  @override
  Future<List<int>> getHourlyStepsForDate(DateTime date) async {
    _ensureListening();

    final now = DateTime.now();
    final isToday = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;

    final dateKey = _dateKey(date);

    if (isToday) {
      try {
        final result = await _methodChannel
            .invokeMethod<List<dynamic>>('getTodayHourlySteps');
        if (result == null) {
          return List<int>.filled(24, 0);
        }
        return result.map((e) => (e as num).toInt()).toList();
      } catch (e) {
        if (kDebugMode) {
          print('getTodayHourlySteps error: $e');
        }
        return List<int>.filled(24, 0);
      }
    }

    // read from history
    try {
      final result = await _methodChannel
          .invokeMethod<List<dynamic>>('getHourlyStepsForDate', dateKey);
      if (result == null) {
        return List<int>.filled(24, 0);
      }
      return result.map((e) => (e as num).toInt()).toList();
    } catch (e) {
      if (kDebugMode) {
        print('getHourlyStepsForDate error: $e');
      }
      return List<int>.filled(24, 0);
    }
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    _stepsController.close();
  }

  @override
  Stream<int> watchTodaySteps() {
    _ensureListening();
    return _stepsController.stream;
  }

}
