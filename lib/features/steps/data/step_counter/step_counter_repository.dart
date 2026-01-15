
abstract class StepCounterRepository {
  Future<int> getStepsForDate(DateTime date);

  Future<List<int>> getHourlyStepsForDate(DateTime date);

  Stream<int> watchTodaySteps();

  Future<bool> isTrackingEnabled();

  Future<int?> getAchievedGoalForDate(DateTime date);

  Future<int> getGoalStreakUntil(DateTime date);

  Future<void> setTrackingEnabled(bool enabled);


  Future<String> exportDataJson();

  Future<ImportPreview> previewImport(String json);

  Future<ImportResult> importData(
    String json, {
    required ImportMode mode,
    bool importSettings = true,
  });
}

enum RetentionMode { never, days }

class RetentionPolicy {
  const RetentionPolicy({
    required this.mode,
    required this.days,
    required this.lastCleanup,
  });

  final RetentionMode mode;
  final int? days;
  final DateTime? lastCleanup;

  factory RetentionPolicy.fromMap(Map<dynamic, dynamic> map) {
    return RetentionPolicy(
      mode: map['mode'] == 'DAYS' ? RetentionMode.days : RetentionMode.never,
      days: (map['days'] as int?)?.clamp(0, 365),
      lastCleanup: map['last_cleanup'] != null && map['last_cleanup'] != 0
          ? DateTime.fromMillisecondsSinceEpoch(map['last_cleanup'])
          : null,
    );
  }
}

enum ImportMode {
  mergeSkip,
  mergeOverwrite,
  replaceAllHistory,
}

class ImportPreview {
  const ImportPreview({
    required this.schemaVersion,
    required this.daysInFile,
    required this.daysExisting,
    required this.daysNew,
    required this.settingsInFile,
  });

  final int schemaVersion;
  final int daysInFile;
  final int daysExisting;
  final int daysNew;
  final bool settingsInFile;

  factory ImportPreview.fromMap(Map<dynamic, dynamic> map) {
    return ImportPreview(
      schemaVersion: (map['schema_version'] as num?)?.toInt() ?? 0,
      daysInFile: (map['days_in_file'] as num?)?.toInt() ?? 0,
      daysExisting: (map['days_existing'] as num?)?.toInt() ?? 0,
      daysNew: (map['days_new'] as num?)?.toInt() ?? 0,
      settingsInFile: (map['settings_in_file'] as bool?) ?? false,
    );
  }
}

class ImportResult {
  const ImportResult({
    required this.importedDays,
    required this.skippedDays,
    required this.overwrittenDays,
    required this.importedSettings,
  });

  final int importedDays;
  final int skippedDays;
  final int overwrittenDays;
  final bool importedSettings;

  factory ImportResult.fromMap(Map<dynamic, dynamic> map) {
    return ImportResult(
      importedDays: (map['imported_days'] as num?)?.toInt() ?? 0,
      skippedDays: (map['skipped_days'] as num?)?.toInt() ?? 0,
      overwrittenDays: (map['overwritten_days'] as num?)?.toInt() ?? 0,
      importedSettings: (map['imported_settings'] as bool?) ?? false,
    );
  }
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

  @override
  Future<String> exportDataJson() async {
    return '{"schema":"step_counter_export","schema_version":1,"exported_at":"mock","app":{"platform":"mock","package":"mock"},"data":{"days":{},"settings":{},"meta":{},"extras":{}}}';
  }

  @override
  Future<ImportPreview> previewImport(String json) async {
    return const ImportPreview(
      schemaVersion: 1,
      daysInFile: 0,
      daysExisting: 0,
      daysNew: 0,
      settingsInFile: false,
    );
  }

  @override
  Future<ImportResult> importData(
    String json, {
    required ImportMode mode,
    bool importSettings = true,
  }) async {
    return const ImportResult(
      importedDays: 0,
      skippedDays: 0,
      overwrittenDays: 0,
      importedSettings: false,
    );
  }
}
