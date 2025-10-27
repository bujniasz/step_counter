import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/goal_store.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const int _center = 10000;
  final PageController _controller = PageController(initialPage: _center);

  late final DateTime _today = DateTime.now();
  late DateTime _current = _truncate(_today);
  int? _goal;

  static DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _shiftDay(DateTime d, int offset) => DateTime(d.year, d.month, d.day + offset);
  int _indexFor(DateTime day) => _center + day.difference(_truncate(_today)).inDays;

  // ===== Założenia (później zrobimy edycję w UI)
  static const double _strideMeters = 0.78; // długość kroku
  static const double _cadenceSpm = 100;    // kroki/min
  static const double _weightKg = 70;       // waga użytkownika
  static const double _metWalking = 3.5;    // MET dla marszu

  // ===== Obliczenia metryk
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
    _controller.animateToPage(
      _indexFor(targetDay),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ===== MOCK: 24 "godzinne" biny aktywności (większe wartości w ciągu dnia)
  List<int> _mockHourlyFor(DateTime day) {
    final d = _truncate(day);
    final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);
    return List<int>.generate(24, (h) {
      final base = ((seed * 73 + h * 31) % 9) + 1; // 1..9
      final isDay = h >= 7 && h <= 21;
      return base * (isDay ? 250 : 60); // „dzienne” piki
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pl', 'PL'),
    );
    if (picked != null) _jumpTo(_truncate(picked));
  }

  Future<void> _editGoal() async {
    int tmp = _goal ?? 8000;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SizedBox(
          height: 360,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ustaw cel dzienny (kroki)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setS) {
                    return Column(
                      children: [
                        Slider(
                          value: tmp.toDouble(),
                          min: 2000,
                          max: 20000,
                          divisions: (20000 - 2000) ~/ 500,
                          label: '$tmp',
                          onChanged: (v) => setS(() => tmp = v.round()),
                        ),
                        Text('Wybrano: $tmp kroków'),
                      ],
                    );
                  },
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, tmp),
                      child: const Text('Zapisz'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
  }

    
  int _mockStepsFor(DateTime day) {
    final d = _truncate(day);
    final seed = d.millisecondsSinceEpoch ~/ (24 * 3600 * 1000);   
    final base = (seed % 7000) + 1500;   
    return base;
  }


  @override
  Widget build(BuildContext context) {
    final header = DateFormat('EEEE, d MMMM y').format(_current);
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
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Następny dzień',
                onPressed: () => _go(1),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _current = _dateFromIndex(i)),
            itemBuilder: (context, index) {
              final date = _dateFromIndex(index);
                
              final steps = _mockStepsFor(date);
              final goal = _goal ?? 8000;   
              final progress = (steps / goal).clamp(0.0, 1.0);
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
                  _HourlyChart(data: _mockHourlyFor(date)),
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
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Ustawienia'));
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
            Row(
              children: [
                Text('Kroki', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Zmień cel',
                  icon: const Icon(Icons.edit),
                  onPressed: onEditGoal,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$steps', style: theme.textTheme.displaySmall),
                Text('cel: $goal', style: theme.textTheme.labelLarge),
              ],
            ),
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
  final String durationHm;   // "hh:mm"
  final double distanceKm;   // np. 3.12
  final int caloriesKcal;    // np. 210

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
  final List<int> data; // 24 wartości

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = (data.reduce((a, b) => a > b ? a : b)).toDouble();
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
                  maxY: maxY * 1.2, // trochę zapasu nad najwyższym słupkiem
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 18,
                        getTitlesWidget: (value, meta) {
                          final h = value.toInt();
                          if (h % 3 != 0) return const SizedBox.shrink(); // podpis co 3h
                          return Text('$h', style: Theme.of(context).textTheme.labelSmall);
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
