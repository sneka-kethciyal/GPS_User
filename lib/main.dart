import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'providers/location_provider.dart';
import 'services/sync_service.dart';
import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required by flutter_foreground_task to wire up the background isolate
  // communication port before any other initialisation happens.
  FlutterForegroundTask.initCommunicationPort();

  // Set system navigation overlay styling for pastel aesthetic
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.cardBackground,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Firebase connected to ebt-expense-geo-tracker
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint(
      '[Firebase] Initialized successfully for project ebt-expense-geo-tracker',
    );
  } catch (e) {
    debugPrint('[Firebase] Initialization notice: $e');
  }

  // Initialize background network sync listener
  SyncService.instance.initialize();

  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: MaterialApp(
        title: 'EBT Expense Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light, // Set clean pastel light theme
        home: const WithForegroundTask(child: AuthGate()),
      ),
    );
  }
}
