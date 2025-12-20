
abstract class StepCounterRepository {
  Future<int> getStepsForDate(DateTime date);

  Future<List<int>> getHourlyStepsForDate(DateTime date);

  Stream<int> watchTodaySteps();

  Future<bool> isTrackingEnabled();

  Future<int?> getAchievedGoalForDate(DateTime date);

  Future<int> getGoalStreakUntil(DateTime date);

  Future<void> setTrackingEnabled(bool enabled);
}


class MockStepCounterRepository implements StepCounterRepository {
  const MockStepCounterRepository();

  DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);

  int _stepsForDateSync(DateTime day) {
    final d = _truncate(day);
    final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);
    final base = (seed % 7000) + 1500;
    return base;
  }

  List<int> _hourlyStepsForDateSync(DateTime day) {
    final d = _truncate(day);
    final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);
    return List<int>.generate(24, (h) {
      final base = ((seed * 73 + h * 31) % 9) + 1;
      final isDay = h >= 7 && h <= 21;
      return base * (isDay ? 250 : 60);
    });
  }

  @override
  Future<int> getStepsForDate(DateTime day) async {
    return _stepsForDateSync(day);
  }

  @override
  Future<List<int>> getHourlyStepsForDate(DateTime day) async {
    return _hourlyStepsForDateSync(day);
  }

  @override
  Stream<int> watchTodaySteps() async* {
    yield _stepsForDateSync(DateTime.now());
  }

  @override
  Future<bool> isTrackingEnabled() async {
    // Mock
    return true;
  }

  @override
  Future<void> setTrackingEnabled(bool enabled) async {
    // Mock
  }

  @override
  Future<int?> getAchievedGoalForDate(DateTime day) async {
    // Proste: uznaj, że celem jest 8000 i jeśli mockowane kroki >= 8000, to cel spełniony.
    final steps = _stepsForDateSync(_truncate(day));
    const goal = 8000;
    return steps >= goal ? goal : null;
  }

  @override
  Future<int> getGoalStreakUntil(DateTime day) async {
    var streak = 0;
    var current = _truncate(day);
    while (true) {
      final achieved = await getAchievedGoalForDate(current);
      if (achieved == null) break;
      streak++;
      current = current.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
