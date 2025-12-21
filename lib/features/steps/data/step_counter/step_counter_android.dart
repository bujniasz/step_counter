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

  @override
  Future<bool> isTrackingEnabled() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isTrackingEnabled');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) async {
    try {
      if (enabled) {
        await _methodChannel.invokeMethod('startTrackingService');
      } else {
        await _methodChannel.invokeMethod('stopTrackingService');
      }
    } catch (_) {
    }
  }

  @override
  Future<int?> getAchievedGoalForDate(DateTime date) async {
    if (kIsWeb) return null;
    final dateKey = _dateKey(date);
    try {
      final result = await _methodChannel.invokeMethod<int>(
        'getAchievedGoalForDate',
        dateKey,
      );
      if (result == null || result <= 0) return null;
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('getAchievedGoalForDate error: $e');
      }
      return null;
    }
  }

  @override
  Future<int> getGoalStreakUntil(DateTime date) async {
    var streak = 0;
    var current = DateTime(date.year, date.month, date.day);

    while (true) {
      final achieved = await getAchievedGoalForDate(current);
      if (achieved == null) break;
      streak++;
      current = current.subtract(const Duration(days: 1));
    }

    return streak;
  }

  // ─────────────────────────────────────────
  // Import / Export
  // ─────────────────────────────────────────
  @override
  Future<String> exportDataJson() async {
    try {
      final json = await _methodChannel.invokeMethod<String>('exportData');
      return json ?? '';
    } catch (e) {
      if (kDebugMode) {
        print('exportData error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<ImportPreview> previewImport(String json) async {
    try {
      final map = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'previewImport',
        json,
      );
      return ImportPreview.fromMap(map ?? const {});
    } catch (e) {
      if (kDebugMode) {
        print('previewImport error: $e');
      }
      rethrow;
    }
  }

  String _modeToNative(ImportMode mode) {
    switch (mode) {
      case ImportMode.mergeSkip:
        return 'MERGE_SKIP';
      case ImportMode.mergeOverwrite:
        return 'MERGE_OVERWRITE';
      case ImportMode.replaceAllHistory:
        return 'REPLACE_ALL_HISTORY';
    }
  }

  @override
  Future<ImportResult> importData(
    String json, {
    required ImportMode mode,
    bool importSettings = true,
  }) async {
    try {
      final map = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'importData',
        {
          'json': json,
          'mode': _modeToNative(mode),
          'importSettings': importSettings,
        },
      );
      return ImportResult.fromMap(map ?? const {});
    } catch (e) {
      if (kDebugMode) {
        print('importData error: $e');
      }
      rethrow;
    }
  }

}
