import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth/auth_repository.dart';
import 'database/app_database.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

late final AuthRepository authRepository;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  authRepository = AuthRepository(AppDatabase.instance);
  await ThemeController.instance.load();
  runApp(const GestorApp());
}

class GestorApp extends StatelessWidget {
  const GestorApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ThemeController.instance,
    builder: (context, _) => MaterialApp(
      title: 'Sistema Escolar SZR',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    ),
  );
}
