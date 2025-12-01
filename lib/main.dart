import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/steps/presentation/pages/pages.dart';
import 'features/steps/data/step_counter/step_counter_repository.dart';
import 'features/steps/data/step_counter/step_counter_android.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pl_PL';
  await initializeDateFormatting('pl_PL', null);
  runApp(const StepCounterApp());
}

class StepCounterApp extends StatelessWidget {
  const StepCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Counter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pl', 'PL'),
        Locale('en', 'US'),
      ],

      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final StepCounterRepository _stepRepository;

  int _index = 0;

  static const _titles = ['Step Counter', 'Step Counter'];

  @override
  void initState() {
    super.initState();

    // On Android we use an actual step counter
    // Mocked for other platforms
    if (!kIsWeb && Platform.isAndroid) {
      _stepRepository = const AndroidStepCounterRepository();
    } else {
      _stepRepository = const MockStepCounterRepository();
    }
  }

  void _showPermissionsInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Informacje'),
        content: const Text(
          'W celu zapewnienia nieprzerwanej pracy krokomierza:\n\n'
          '• przypmin aplikację w sekcji „Ostatnie”,\n'
          '• pozwól aplikacji na dostęp do „Aktywność fizyczna”,\n'
          '• włącz „Autostart”,\n'
          '• ustaw „Oszczędzanie energii” na „Bez ograniczeń”.\n\n'
          'Opcje te znajdziesz w ustawieniach systemowych aplikacji.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(stepRepository: _stepRepository),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
      title: Text(_titles[_index]),
      actions: [
        if (_index == 0)
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Informacje',
            onPressed: () => _showPermissionsInfo(context),
          ),
      ],
    ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.directions_walk), label: 'Dziś'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ustawienia'),
        ],
      ),
    );
  }
}