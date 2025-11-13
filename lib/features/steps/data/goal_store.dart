import 'package:shared_preferences/shared_preferences.dart';

class GoalStore {
  static const _kKey = 'daily_goal_steps';
  static const int _defaultGoal = 8000;

  static int? _cachedGoal;

  static int get cachedGoal => _cachedGoal ?? _defaultGoal;

  static Future<int> getGoal() async {
    if (_cachedGoal != null) {
      return _cachedGoal!;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedGoal = prefs.getInt(_kKey) ?? _defaultGoal;
    return _cachedGoal!;
  }

  static Future<void> setGoal(int steps) async {
    _cachedGoal = steps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kKey, steps);
  }
}