import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/goal_store.dart';
import '../../data/body_params_store.dart';
import '../../data/step_counter/step_counter_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:step_counter/core/permissions/activity_recognition_permission.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.stepRepository,
    });

  final StepCounterRepository stepRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const int _center = 10000;
  final PageController _controller = PageController(initialPage: _center);

  late final DateTime _today = DateTime.now();
  late DateTime _current = _truncate(_today);
  int _goal = GoalStore.cachedGoal;

  int? _cachedTodaySteps;
  List<int>? _cachedTodayHourly;

  late BodyParamsSettings _bodySettings;

  static DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _shiftDay(DateTime d, int offset) => DateTime(d.year, d.month, d.day + offset);
  int _indexFor(DateTime day) => _center + day.difference(_truncate(_today)).inDays;

  // assumptions
  static const double _cadenceSpm = 100;
  static const double _metWalking = 3.5;

  int _durationMinutes(int steps) => (steps / _cadenceSpm).round();

  double _distanceKm(int steps) {
    final stride = BodyParamsStore.effectiveStrideMeters(_bodySettings);
    return (steps * stride) / 1000.0;
  }

  int _caloriesKcal(int steps) {
    final hours = _durationMinutes(steps) / 60.0;
    final weight = BodyParamsStore.effectiveWeightKg(_bodySettings);
    return (_metWalking * weight * hours).round();
  }

  String _formatHm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  
  DateTime _dateFromIndex(int index) {
    final offset = index - _center;
    final d = _truncate(_today);
    return DateTime(d.year, d.month, d.day + offset);
  }

  
  void _jumpTo(DateTime day) {
    final base = _truncate(_today);
    final delta = day.difference(base).inDays; 
    _controller.jumpToPage(_center + delta);
  }

  void _go(int offsetDays) {
    final targetDay = _shiftDay(_current, offsetDays);
    if (targetDay.isAfter(_truncate(_today))) return;
    _controller.animateToPage(
      _indexFor(targetDay),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // mocked data
  // List<int> _mockHourlyFor(DateTime day) {
  //   final d = _truncate(day);
  //   final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);
  //   return List<int>.generate(24, (h) {
  //     final base = ((seed * 73 + h * 31) % 9) + 1;
  //     final isDay = h >= 7 && h <= 21;
  //     return base * (isDay ? 250 : 60);
  //   });
  // }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _current,
      firstDate: DateTime(2025),
      lastDate: _truncate(_today),
      locale: const Locale('pl', 'PL'),
    );
    if (picked != null) _jumpTo(_truncate(picked));
  }

  Future<void> _editGoal() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _GoalEditSheet(initial: _goal),
    );
    
    if (picked != null) {
      await GoalStore.setGoal(picked);
      setState(() => _goal = picked);
    }
  }

  @override
  void initState() {
    super.initState();

    _bodySettings = BodyParamsStore.settingsNotifier.value;
    BodyParamsStore.settingsNotifier.addListener(_onBodySettingsChanged);

    GoalStore.getGoal().then((v) => setState(() => _goal = v));

    // Android 10+ req
    if (!kIsWeb && Platform.isAndroid) {
      ensureActivityRecognitionPermission();
    }

    // Na start pobierz dzisiejsze dane i zapisz w cache.
    final today = DateTime.now();
    widget.stepRepository.getStepsForDate(today).then((value) {
      if (!mounted) return;
      setState(() {
        _cachedTodaySteps = value;
      });
    });
    widget.stepRepository.getHourlyStepsForDate(today).then((value) {
      if (!mounted) return;
      setState(() {
        _cachedTodayHourly = value;
      });
    });

  }

  void _onBodySettingsChanged() {
    setState(() {
      _bodySettings = BodyParamsStore.settingsNotifier.value;
    });
  }
    
  // int _mockStepsFor(DateTime day) {
  //   final d = _truncate(day);
  //   final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);   
  //   final base = (seed % 7000) + 1500;   
  //   return base;
  // }

  @override
  void dispose() {
    BodyParamsStore.settingsNotifier.removeListener(_onBodySettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = DateFormat('EEEE, d MMMM y').format(_current);
    final bool isToday = _truncate(_current) == _truncate(_today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Poprzedni dzień',
                onPressed: () => _go(-1),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDate, 
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        header[0].toUpperCase() + header.substring(1),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: isToday
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).iconTheme.color,
                ),
                tooltip: isToday ? 'To jest dzisiaj' : 'Następny dzień',
                onPressed: isToday ? null : () => _go(1),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _center + 1,
            onPageChanged: (i) => setState(() => _current = _dateFromIndex(i)),
            itemBuilder: (context, index) {
              final date = _dateFromIndex(index);
              final today = DateTime.now();
              final isToday = _isSameDate(date, today);

              if (isToday) {
                // today - live update
                return StreamBuilder<int>(
                  stream: widget.stepRepository.watchTodaySteps(),
                  builder: (context, stepsSnapshot) {
                    if (stepsSnapshot.hasData) {
                      _cachedTodaySteps = stepsSnapshot.data;
                    }
                    final steps = _cachedTodaySteps ?? stepsSnapshot.data ?? 0;
                    final goal = _goal;
                    final progress = goal > 0
                        ? (steps / goal).clamp(0.0, 1.0)
                        : 0.0;

                    return FutureBuilder<List<int>>(
                      future: widget.stepRepository
                          .getHourlyStepsForDate(date),
                      builder: (context, hourlySnapshot) {
                        if (hourlySnapshot.hasData) {
                            _cachedTodayHourly = hourlySnapshot.data;
                        }

                        final hourlyData =
                           _cachedTodayHourly ??
                            hourlySnapshot.data ??
                            const <int>[];

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _StepsCard(
                              date: date,
                              steps: steps,
                              goal: goal,
                              progress: progress,
                              onEditGoal: _editGoal,
                              stepRepository: widget.stepRepository,
                            ),
                            const SizedBox(height: 12),
                            _HourlyChart(
                              data: hourlyData,
                            ),
                            const SizedBox(height: 12),
                            _MetricsCard(
                              durationHm: _formatHm(_durationMinutes(steps)),
                              distanceKm: _distanceKm(steps),
                              caloriesKcal: _caloriesKcal(steps),
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      },
                    );
                  },
                );
              }

              // other days - one time download
              return FutureBuilder<int>(
                future: widget.stepRepository.getStepsForDate(date),
                builder: (context, stepsSnapshot) {
                  final steps = stepsSnapshot.data ?? 0;
                  final goal = _goal;
                  final progress = goal > 0
                      ? (steps / goal).clamp(0.0, 1.0)
                      : 0.0;

                  return FutureBuilder<List<int>>(
                    future: widget.stepRepository
                        .getHourlyStepsForDate(date),
                    builder: (context, hourlySnapshot) {
                      final hourlyData =
                          hourlySnapshot.data ?? const <int>[];

                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _StepsCard(
                            date: date,
                            steps: steps,
                            goal: goal,
                            progress: progress,
                            onEditGoal: _editGoal,
                            stepRepository: widget.stepRepository,
                          ),
                          const SizedBox(height: 12),
                          _HourlyChart(
                            data: hourlyData,
                          ),
                          const SizedBox(height: 12),
                          _MetricsCard(
                            durationHm: _formatHm(_durationMinutes(steps)),
                            distanceKm: _distanceKm(steps),
                            caloriesKcal: _caloriesKcal(steps),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),     
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.stepRepository,
  });

  final StepCounterRepository stepRepository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _trackingEnabled;
  bool _trackingBusy = false;

  bool? _goalNotifEnabled;
  bool _goalNotifBusy = false;
  static const MethodChannel _methodChannel = MethodChannel('step_counter/methods');

  late BodyParamsSettings _settings;

  @override
  void initState() {
    super.initState();
    _loadTracking();

    _loadGoalNotification();

    _settings = BodyParamsStore.settingsNotifier.value;
    BodyParamsStore.settingsNotifier.addListener(_onExternalSettingsChanged);
  }

  @override
  void dispose() {
    BodyParamsStore.settingsNotifier.removeListener(_onExternalSettingsChanged);
    super.dispose();
  }

  Future<void> _loadTracking() async {
    final enabled = await widget.stepRepository.isTrackingEnabled();
    if (!mounted) return;
    setState(() {
      _trackingEnabled = enabled;
    });
  }

  Future<void> _onTrackingChanged(bool value) async {
    if (_trackingBusy) return;
    setState(() {
      _trackingEnabled = value;
      _trackingBusy = true;
    });
    try {
      await widget.stepRepository.setTrackingEnabled(value);
    } finally {
      if (mounted) {
        setState(() => _trackingBusy = false);
      }
    }
  }

  Future<void> _loadGoalNotification() async {
    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        _goalNotifEnabled = true;
      });
      return;
    }
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('isGoalNotificationEnabled');
      setState(() {
        _goalNotifEnabled = result ?? true;
      });
    } catch (_) {
      setState(() {
        _goalNotifEnabled = true;
      });
    }
  }

  Future<void> _onGoalNotificationChanged(bool value) async {
    if (_goalNotifBusy) return;
    setState(() {
      _goalNotifEnabled = value;
      _goalNotifBusy = true;
    });

    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        _goalNotifBusy = false;
      });
      return;
    }

    try {
      await _methodChannel.invokeMethod(
        "setGoalNotificationEnabled",
        value,
      );
    } catch (_) {
      // Można ewentualnie zareagować, ale UI zostawiamy jak jest
    } finally {
      if (mounted) {
        setState(() {
          _goalNotifBusy = false;
        });
      }
    }
  }

  void _onExternalSettingsChanged() {
    setState(() {
      _settings = BodyParamsStore.settingsNotifier.value;
    });
  }

  String _strideSummary(BodyParamsSettings s) {
    final stride = BodyParamsStore.effectiveStrideMeters(s);
    switch (s.strideSource) {
      case StrideSource.systemDefault:
        return 'Domyślna długość kroku (0.78 m)';
      case StrideSource.manual:
        return 'Własna długość kroku (${stride.toStringAsFixed(2)} m)';
      case StrideSource.fromHeight:
        final base = 'Z wzrostu i płci (${stride.toStringAsFixed(2)} m)';
        if (s.heightCm != null && s.gender != null) {
          final genderText =
              s.gender == Gender.female ? 'kobieta' : 'mężczyzna';
          return '$base – $genderText, ${s.heightCm} cm';
        }
        return base;
    }
  }

  String _weightSummary(BodyParamsSettings s) {
    final weight = BodyParamsStore.effectiveWeightKg(s);
    switch (s.weightSource) {
      case WeightSource.systemDefault:
        return 'Domyślna waga (70 kg)';
      case WeightSource.manual:
        return 'Własna waga (${weight.toStringAsFixed(1)} kg)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackingEnabled = _trackingEnabled;

    const sectionSpacing = SizedBox(height: 24);
    const tileSpacing = SizedBox(height: 4);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        //
        // ─────────────────────────────────────────
        // SEKCJA 1 — ŚLEDZENIE KROKÓW
        // ─────────────────────────────────────────
        Text(
          'Ogólne',
          style: theme.textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        tileSpacing,
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              'Śledzenie kroków w tle',
              style: theme.textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              trackingEnabled == true
                  ? 'Śledzenie kroków jest włączone.'
                  : 'Śledzenie kroków jest wyłączone.',
              style: theme.textTheme.bodySmall,
            ),
            value: trackingEnabled ?? false,
            onChanged: (trackingEnabled == null || _trackingBusy)
                ? null
                : _onTrackingChanged,
          ),
        ),

        // --- OPIS POD PIERWSZYM SWITCHEM ---
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: Text(
            'Gdy funkcja jest wyłączona, kroki nie są zliczane, a serwis nie '
            'wznowi pracy automatycznie po restarcie telefonu.',
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
        ),

        // 🌟 DUŻY, CZYTELNY ODDZIELACZ SEKCJI
        const SizedBox(height: 20),

        // --- DRUGI SWITCH – osobna sekcja ---
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              'Powiadom o spełnieniu celu',
              style: theme.textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _goalNotifEnabled == false
                  ? 'Powiadomienie po osiągnięciu celu jest wyłączone.'
                  : 'Otrzymasz powiadomienie, gdy dzienny cel zostanie osiągnięty.',
              style: theme.textTheme.bodySmall,
            ),
            value: _goalNotifEnabled ?? true,
            onChanged: (_goalNotifEnabled == null || _goalNotifBusy)
                ? null
                : _onGoalNotificationChanged,
          ),
        ),

        sectionSpacing,
        Divider(height: 1, thickness: 1, color: theme.dividerColor.withOpacity(0.4)),
        sectionSpacing,

        //
        // ─────────────────────────────────────────
        // SEKCJA 2 — DYSTANS
        // ─────────────────────────────────────────
        Text(
          'Dystans',
          style: theme.textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        tileSpacing,
        _SettingsEntryTile(
          title: 'Dostosuj długość kroku',
          subtitle: _strideSummary(_settings),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const StrideSettingsPage(),
              ),
            );
          },
        ),

        sectionSpacing,
        Divider(height: 1, thickness: 1, color: theme.dividerColor.withOpacity(0.4)),
        sectionSpacing,

        //
        // ─────────────────────────────────────────
        // SEKCJA 3 — KALORIE
        // ─────────────────────────────────────────
        Text(
          'Kalorie',
          style: theme.textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        tileSpacing,
        _SettingsEntryTile(
          title: 'Dostosuj spalane kalorie',
          subtitle: _weightSummary(_settings),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WeightSettingsPage(),
              ),
            );
          },
        ),

        const SizedBox(height: 40),
      ],
    );
  }
}

class StrideSettingsPage extends StatefulWidget {
  const StrideSettingsPage({super.key});

  @override
  State<StrideSettingsPage> createState() => _StrideSettingsPageState();
}

class _StrideSettingsPageState extends State<StrideSettingsPage> {
  late BodyParamsSettings _settings;
  late final TextEditingController _heightController;
  late final TextEditingController _strideController;

  @override
  void initState() {
    super.initState();
    _settings = BodyParamsStore.settingsNotifier.value;

    _heightController = TextEditingController(
      text: _settings.heightCm?.toString() ?? '',
    );
    _strideController = TextEditingController(
      text: _settings.manualStrideMeters?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _heightController.dispose();
    _strideController.dispose();
    super.dispose();
  }

  Future<void> _updateSettings(BodyParamsSettings newSettings) async {
    setState(() {
      _settings = newSettings;
    });
    await BodyParamsStore.save(newSettings);
  }

  double? _parseDouble(String value) {
    final normalized = value.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  int? _parseInt(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;
    return int.tryParse(digitsOnly);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Długość kroku'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Dystans (długość kroku)',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          RadioListTile<StrideSource>(
            value: StrideSource.systemDefault,
            groupValue: _settings.strideSource,
            onChanged: (value) {
              if (value == null) return;
              _updateSettings(
                _settings.copyWith(strideSource: value),
              );
            },
            title: const Text('Domyślna długość kroku'),
            subtitle: const Text('Użyj wartości 0.78 m'),
          ),
          RadioListTile<StrideSource>(
            value: StrideSource.manual,
            groupValue: _settings.strideSource,
            onChanged: (value) {
              if (value == null) return;
              _updateSettings(
                _settings.copyWith(strideSource: value),
              );
            },
            title: const Text('Własna długość kroku'),
            subtitle: const Text('Podaj długość kroku w metrach'),
          ),
          if (_settings.strideSource == StrideSource.manual) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _strideController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Długość kroku [m] (max. 2)',
                hintText: 'np. 0.78',
              ),
              onChanged: (value) {
                double? d = _parseDouble(value);

                if (d != null) {
                  // Zakres 0–2
                  if (d < 0) d = 0;
                  if (d > 2) d = 2;
                  // Maks 2 miejsca po przecinku
                  d = double.parse(d.toStringAsFixed(2));
                }

                _updateSettings(
                  _settings.copyWith(
                    manualStrideMeters: d,
                    clearManualStride: value.trim().isEmpty,
                  ),
                );
              },
            ),
          ],
          RadioListTile<StrideSource>(
            value: StrideSource.fromHeight,
            groupValue: _settings.strideSource,
            onChanged: (value) {
              if (value == null) return;
              _updateSettings(
                _settings.copyWith(strideSource: value),
              );
            },
            title: const Text('Wylicz z wzrostu i płci'),
            subtitle: const Text(
              'kobieta: 0.413 × wzrost\nmężczyzna: 0.415 × wzrost',
            ),
          ),
          if (_settings.strideSource == StrideSource.fromHeight) ...[
            const SizedBox(height: 8),
            Text(
              'Płeć',
              style: theme.textTheme.bodyMedium,
            ),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Kobieta'),
                  selected: _settings.gender == Gender.female,
                  onSelected: (_) {
                    _updateSettings(
                      _settings.copyWith(gender: Gender.female),
                    );
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Mężczyzna'),
                  selected: _settings.gender == Gender.male,
                  onSelected: (_) {
                    _updateSettings(
                      _settings.copyWith(gender: Gender.male),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Wzrost [cm] (max. 300)',
                hintText: 'np. 175',
              ),
              onChanged: (value) {
                int? h = _parseInt(value);

                if (h != null) {
                  if (h < 0) h = 0;
                  if (h > 300) h = 300;
                }

                _updateSettings(
                  _settings.copyWith(
                    heightCm: h,
                    clearHeight: value.trim().isEmpty,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}


class WeightSettingsPage extends StatefulWidget {
  const WeightSettingsPage({super.key});

  @override
  State<WeightSettingsPage> createState() => _WeightSettingsPageState();
}

class _WeightSettingsPageState extends State<WeightSettingsPage> {
  late BodyParamsSettings _settings;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _settings = BodyParamsStore.settingsNotifier.value;

    _weightController = TextEditingController(
      text: _settings.manualWeightKg?.toStringAsFixed(1) ?? '',
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _updateSettings(BodyParamsSettings newSettings) async {
    setState(() {
      _settings = newSettings;
    });
    await BodyParamsStore.save(newSettings);
  }

  double? _parseDouble(String value) {
    final normalized = value.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spalane kalorie'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Kalorie (waga)',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          RadioListTile<WeightSource>(
            value: WeightSource.systemDefault,
            groupValue: _settings.weightSource,
            onChanged: (value) {
              if (value == null) return;
              _updateSettings(
                _settings.copyWith(weightSource: value),
              );
            },
            title: const Text('Domyślna waga'),
            subtitle: const Text('Użyj wartości 70 kg'),
          ),
          RadioListTile<WeightSource>(
            value: WeightSource.manual,
            groupValue: _settings.weightSource,
            onChanged: (value) {
              if (value == null) return;
              _updateSettings(
                _settings.copyWith(weightSource: value),
              );
            },
            title: const Text('Własna waga'),
            subtitle: const Text('Podaj swoją wagę w kilogramach'),
          ),
          if (_settings.weightSource == WeightSource.manual) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _weightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Waga [kg] (max. 300)',
                hintText: 'np. 70',
              ),
              onChanged: (value) {
                double? w = _parseDouble(value);

                if (w != null) {
                  // Zakres 0–300
                  if (w < 0) w = 0;
                  if (w > 300) w = 300;
                  // Maks 2 miejsca po przecinku
                  w = double.parse(w.toStringAsFixed(2));
                }

                _updateSettings(
                  _settings.copyWith(
                    manualWeightKg: w,
                    clearManualWeight: value.trim().isEmpty,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}



class _StepsCard extends StatefulWidget {
  const _StepsCard({
    required this.date,
    required this.steps,
    required this.goal,
    required this.progress,
    required this.onEditGoal,
    required this.stepRepository,
  });

  final DateTime date;
  final int steps;
  final int goal;
  final double progress;
  final VoidCallback onEditGoal;
  final StepCounterRepository stepRepository;

  @override
  State<_StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends State<_StepsCard> {
  int? _achievedGoal;
  int? _streak;
  bool _tooltipVisible = false;

  @override
  void initState() {
    super.initState();
    _loadAchievedGoal();
  }

  @override
  void didUpdateWidget(covariant _StepsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _achievedGoal = null;
      _streak = null;
      _tooltipVisible = false;
      _loadAchievedGoal();
    }
  }

  Future<void> _loadAchievedGoal() async {
    final goal = await widget.stepRepository.getAchievedGoalForDate(widget.date);
    if (!mounted) return;
    setState(() {
      _achievedGoal = goal;
    });
  }

  Future<void> _ensureStreakLoaded() async {
    if (_streak != null) return;
    final s = await widget.stepRepository.getGoalStreakUntil(widget.date);
    if (!mounted) return;
    setState(() {
      _streak = s;
    });
  }

  void _onCheckTapDown(TapDownDetails details) async {
    await _ensureStreakLoaded();
    if (!mounted) return;
    setState(() {
      _tooltipVisible = true;
    });
  }

  void _onCheckTapEnd([dynamic _]) {
    if (!mounted) return;
    setState(() {
      _tooltipVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (widget.progress * 100).clamp(0, 100).toStringAsFixed(0);

    return Card(
      elevation: 0,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kroki', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('cel: ${widget.goal}',
                        style: theme.textTheme.labelLarge),
                    TextButton.icon(
                      onPressed: widget.onEditGoal,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Zmień cel'),
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 🔢 kroki + ✔ fajka po prawej, POD "Zmień cel"
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.steps}',
                        style: theme.textTheme.displaySmall,
                      ),
                    ),
                    if (_achievedGoal != null)
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapDown: _onCheckTapDown,
                        onTapUp: _onCheckTapEnd,
                        onTapCancel: _onCheckTapEnd,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(
                            Icons.check_circle,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: widget.progress,
                          minHeight: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$percent%', style: theme.textTheme.labelLarge),
                  ],
                ),
              ],
            ),
          ),

          // 📝 TOOLTIP – nad kartą, nie zasłania "Zmień cel"
          if (_tooltipVisible && _achievedGoal != null && _streak != null)
            Positioned(
              right: 16,
              top: 8,
              child: _GoalTooltip(
                goal: _achievedGoal!,
                streak: _streak!,
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalTooltip extends StatelessWidget {
  const _GoalTooltip({
    required this.goal,
    required this.streak,
  });

  final int goal;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DefaultTextStyle(
          style: theme.textTheme.bodySmall!.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cel: $goal kroków'),
              const SizedBox(height: 2),
              Text('Streak: $streak dni z rzędu'),
            ],
          ),
        ),
      ),
    );
  }
}


class _MetricsCard extends StatelessWidget {
  const _MetricsCard({
    required this.durationHm,
    required this.distanceKm,
    required this.caloriesKcal,
  });
  final String durationHm;
  final double distanceKm;
  final int caloriesKcal;

  @override
  Widget build(BuildContext context) {
    final km = NumberFormat('#,##0.00', 'pl_PL').format(distanceKm);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _MetricTile(label: 'Czas', value: durationHm, sub: 'hh:mm'),
            _MetricTile(label: 'Dystans', value: km, sub: 'km'),
            _MetricTile(label: 'Kalorie', value: '$caloriesKcal', sub: 'kcal'),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, required this.sub});
  final String label;
  final String value;
  final String sub;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelMedium),
        const SizedBox(height: 6),
        Text(value, style: t.titleLarge),
        const SizedBox(height: 2),
        Text(sub, style: t.bodySmall),
      ],
    );
  }
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.data});

  final List<int> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final int maxData =
        data.isEmpty ? 0 : data.reduce((a, b) => a > b ? a : b);

    // base maximym
    final double baseMax = maxData == 0 ? 1000 : maxData.toDouble();

    final double rawStep = baseMax / 4.0;

    int stepHundreds = ((rawStep + 99) ~/ 100) * 100;

    if (stepHundreds == 0) {
      stepHundreds = 100;
    }

    final double yStep = stepHundreds.toDouble();
    final double tickMaxY = yStep * 4;

    String formatHour(int h) => h.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aktywność godzinowa', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: tickMaxY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) =>
                          theme.colorScheme.surface.withOpacity(0.95),
                      tooltipBorderRadius: BorderRadius.circular(12),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem:
                          (group, groupIndex, rod, rodIndex) {
                        final hour = group.x;
                        final start = formatHour(hour);
                        final end = formatHour((hour + 1) % 24);
                        final steps = rod.toY.toInt();

                        final style = theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        );

                        return BarTooltipItem(
                          '$start:00 - $end:00\n$steps',
                          style ?? const TextStyle(),
                        );
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yStep,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yStep,
                        getTitlesWidget: (value, meta) {
                          if (value < 0) return const SizedBox.shrink();
                          return Text(
                            value.toInt().toString(),
                            style: theme.textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 18,
                        getTitlesWidget: (value, meta) {
                          final h = value.toInt();
                          if (h % 3 != 0) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            '$h',
                            style: theme.textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(
                    data.length,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: data[i].toDouble(),
                          width: 8,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalEditSheet extends StatefulWidget {
  const _GoalEditSheet({required this.initial});
  final int initial;
  @override
  State<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<_GoalEditSheet> {
  late int tmp;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    tmp = widget.initial.clamp(500, 20000);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final sliderValue = tmp.clamp(500, 20000).toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ustaw cel dzienny (kroki)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Slider(
            value: sliderValue,
            min: 500,
            max: 20000,
            divisions: (20000 - 500) ~/ 500, // step = 500
            label: '${sliderValue.round()}',
            onChanged: (v) => setState(() => tmp = v.round()),
          ),
          Text('Z suwaka: ${sliderValue.round()} kroków'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Lub wpisz własny cel (0–200 000)',
              helperText: 'Pole działa niezależnie od suwaka',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Anuluj'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = int.tryParse(_ctrl.text);
                  final valid = v != null && v >= 0 && v <= 200000;
                  Navigator.pop(context, valid ? v : tmp);
                },
                child: const Text('Zapisz'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _SettingsEntryTile extends StatelessWidget {
  const _SettingsEntryTile({
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
