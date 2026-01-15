import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/steps/presentation/pages/pages.dart';
import 'features/steps/data/step_counter/step_counter_repository.dart';
import 'features/steps/data/step_counter/step_counter_android.dart';
import 'features/steps/data/body_params_store.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/steps/data/goal_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pl_PL';
  await initializeDateFormatting('pl_PL', null);
  await GoalStore.syncCurrentGoalToNative();
  await BodyParamsStore.load();
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
          'W celu zapewnienia prawidłowej i nieprzerwanej pracy krokomierza:\n\n'
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

  Future<void> _showDataManagementSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Zarządzanie danymi'),
                subtitle: Text('Eksport i import historii kroków'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Eksportuj dane'),
                onTap: () async {
                  Navigator.pop(context);
                  await _exportData(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Importuj dane'),
                onTap: () async {
                  Navigator.pop(context);
                  await _importData(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportData(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eksport nie jest dostępny w wersji web.')),
      );
      return;
    }

    try {
      final json = await _stepRepository.exportDataJson();
      if (json.isEmpty) {
        throw Exception('empty_export');
      }

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now();
      final y = ts.year.toString().padLeft(4, '0');
      final m = ts.month.toString().padLeft(2, '0');
      final d = ts.day.toString().padLeft(2, '0');
      final hh = ts.hour.toString().padLeft(2, '0');
      final mm = ts.minute.toString().padLeft(2, '0');
      final filename = 'step-counter-export_${y}-${m}-${d}_${hh}-${mm}.json';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(json);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Step Counter — eksport danych',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wyeksportowano dane.')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Export error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się wyeksportować danych.')),
        );
      }
    }
  }

  Future<void> _importData(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import nie jest dostępny w wersji web.')),
      );
      return;
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final bytes = picked.files.first.bytes;
      if (bytes == null) {
        throw Exception('no_bytes');
      }
      final json = String.fromCharCodes(bytes);

      final preview = await _stepRepository.previewImport(json);

      var importSettings = false;
      var mode = ImportMode.mergeSkip;

      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              return AlertDialog(
                title: const Text('Import danych'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('W pliku: ${preview.daysInFile} dni'),
                    Text('Nowe dni: ${preview.daysNew}'),
                    Text('Istniejące dni: ${preview.daysExisting}'),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: importSettings,
                      onChanged: (v) => setState(() => importSettings = v ?? false),
                      title: const Text('Importuj ustawienia'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Tryb importu:'),
                    RadioListTile<ImportMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ImportMode.mergeSkip,
                      groupValue: mode,
                      onChanged: (v) => setState(() => mode = v!),
                      title: const Text('Scal (pomiń istniejące)'),
                    ),
                    RadioListTile<ImportMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ImportMode.mergeOverwrite,
                      groupValue: mode,
                      onChanged: (v) => setState(() => mode = v!),
                      title: const Text('Scal (nadpisz istniejące)'),
                    ),
                    RadioListTile<ImportMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ImportMode.replaceAllHistory,
                      groupValue: mode,
                      onChanged: (v) => setState(() => mode = v!),
                      title: const Text('Zastąp całą historię'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Anuluj'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Importuj'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (proceed != true) return;

      if (mode == ImportMode.replaceAllHistory) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Zastąpić historię?'),
            content: const Text(
              'To usunie obecną historię kroków z tego telefonu i zastąpi ją danymi z pliku.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Zastąp'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }

      final res = await _stepRepository.importData(
        json,
        mode: mode,
        importSettings: importSettings,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Zaimportowano ${res.importedDays} dni (pominięto ${res.skippedDays}).',
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Import error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się zaimportować danych.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(stepRepository: _stepRepository),
      SettingsPage(stepRepository: _stepRepository),
    ];
    return Scaffold(
      appBar: AppBar(
      title: Text(_titles[_index]),
        actions: [
          if (_index == 0) ...[
            IconButton(
              icon: const Icon(Icons.import_export),
              tooltip: 'Import / Eksport',
              onPressed: () => _showDataManagementSheet(context),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Informacje',
              onPressed: () => _showPermissionsInfo(context),
            ),
          ]
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
          BottomNavigationBarItem(icon: Icon(Icons.directions_walk), label: 'Kroki'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ustawienia'),
        ],
      ),
    );
  }
}