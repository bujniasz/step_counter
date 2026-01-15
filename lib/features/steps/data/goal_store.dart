import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class GoalStore {
  static const _kKey = 'daily_goal_steps';
  static const int _defaultGoal = 8000;

  static int? _cachedGoal;

  static int get cachedGoal => _cachedGoal ?? _defaultGoal;

  static const MethodChannel _channel = MethodChannel('step_counter/methods');

  static Future<int> getGoal() async {
    if (_cachedGoal != null) {
      return _cachedGoal!;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedGoal = prefs.getInt(_kKey) ?? _defaultGoal;
    return _cachedGoal!;
  }

  static Future<void> _syncGoalToNative(int steps) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setDailyGoal', steps);
    } catch (_) {
      // ignore
    }
  }

  static Future<void> setGoal(int steps) async {
    _cachedGoal = steps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kKey, steps);
    await _syncGoalToNative(steps);
  }

  static Future<void> syncCurrentGoalToNative() async {
    final steps = await getGoal();
    await _syncGoalToNative(steps);
  }
}