import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'runtime/app_bootstrap.dart';
import 'runtime/app_dependencies.dart';
import 'features/sync/application/sync_trigger.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppBootstrap.production().initialize();
  runApp(MyApp(dependencies: dependencies));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final trigger = widget.dependencies.syncTrigger;
      if (trigger != null) {
        unawaited(trigger.request(SyncTriggerReason.appResume));
      }
    }
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dependencies, widget.dependencies)) {
      unawaited(oldWidget.dependencies.dispose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDependenciesScope(
      dependencies: widget.dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LexiQuest - AI Vocab Learning',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            primary: Colors.deepPurple,
            secondary: Colors.indigo,
            tertiary: Colors.teal,
          ),
          textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
          cardTheme: CardThemeData(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
        ),
        initialRoute: '/login',
        routes: {
          '/login': (context) => LoginScreen(
            guestSessionService: AppDependenciesScope.of(
              context,
            ).guestSessionService,
          ),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const MainNavigationScreen(),
        },
      ),
    );
  }
}
