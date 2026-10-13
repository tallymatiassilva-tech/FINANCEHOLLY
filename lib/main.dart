import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/app_database.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'services/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  await database.open();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(database),
      child: const ChurchFinanceApp(),
    ),
  );
}

class ChurchFinanceApp extends StatelessWidget {
  const ChurchFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Controle Financeiro Igreja',
      debugShowCheckedModeBanner: false,
      themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245a46)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff77c9a5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: state.user == null ? const AuthScreen() : const AppShell(),
    );
  }
}
