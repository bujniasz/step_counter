import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/goal_store.dart';
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

  static DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _shiftDay(DateTime d, int offset) => DateTime(d.year, d.month, d.day + offset);
  int _indexFor(DateTime day) => _center + day.difference(_truncate(_today)).inDays;

  // assumption
  static const double _strideMeters = 0.78;
  static const double _cadenceSpm = 100;
  static const double _weightKg = 70;
  static const double _metWalking = 3.5;

  int _durationMinutes(int steps) => (steps / _cadenceSpm).round();
  double _distanceKm(int steps) => (steps * _strideMeters) / 1000.0;
  int _caloriesKcal(int steps) {
    final hours = _durationMinutes(steps) / 60.0;
    return (_metWalking * _weightKg * hours).round();
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
      
    GoalStore.getGoal().then((v) => setState(() => _goal = v));

    // Android 10+ wymaga runtime permission do liczenia kroków.
    if (!kIsWeb && Platform.isAndroid) {
      // Nie czekamy na wynik – dialog systemowy i tak wyskoczy,
      // a repozytorium zacznie liczyć kroki po przyznaniu uprawnienia.
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

    
  // int _mockStepsFor(DateTime day) {
  //   final d = _truncate(day);
  //   final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);   
  //   final base = (seed % 7000) + 1500;   
  //   return base;
  // }


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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.stepRepository.isTrackingEnabled();
    if (!mounted) return;
    setState(() {
      _trackingEnabled = enabled;
    });
  }

  Future<void> _onChanged(bool value) async {
    if (_busy) return;
    setState(() {
      _trackingEnabled = value;
      _busy = true;
    });
    try {
      await widget.stepRepository.setTrackingEnabled(value);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackingEnabled = _trackingEnabled;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Śledzenie kroków w tle'),
          subtitle: Text(
            trackingEnabled == true
                ? 'Śledzenie kroków jest włączone.'
                : 'Śledzenie kroków jest wyłączone.',
          ),
          value: trackingEnabled ?? false,
          onChanged: (trackingEnabled == null || _busy) ? null : _onChanged,
        ),
        const SizedBox(height: 8),
        Text(
          'Gdy funkcja jest wyłączona, kroki nie są zliczane, a serwis nie '
          'wznowi pracy samoczynnie po restarcie telefonu.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}


class _StepsCard extends StatelessWidget {
  const _StepsCard({
    required this.date,
    required this.steps,
    required this.goal,
    required this.progress,
    required this.onEditGoal,
  });

  final DateTime date;
  final int steps;
  final int goal;
  final double progress;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Card(
      elevation: 0,
      child: Padding(
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
                Text('cel: $goal', style: theme.textTheme.labelLarge),
                TextButton.icon(
                  onPressed: onEditGoal,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Zmień cel'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$steps', style: theme.textTheme.displaySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                  
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
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
