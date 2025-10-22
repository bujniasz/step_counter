import 'package:shared_preferences/shared_preferences.dart';

class GoalStore {
  static const _kKey = 'daily_goal_steps';
  static const int _defaultGoal = 8000;

  static Future<int> getGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kKey) ?? _defaultGoal;
  }

  static Future<void> setGoal(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kKey, steps);
  }
}