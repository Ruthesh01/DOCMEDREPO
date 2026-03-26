import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter/foundation.dart';

import 'app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/notification_provider.dart';
import 'services/local_cache_service.dart';
import 'services/notification_service.dart';
import 'screens/patient_login_screen.dart';
import 'screens/doctor_login_screen.dart';
import 'screens/patient_dashboard_screen.dart';
import 'screens/doctor_dashboard_screen.dart';
import 'screens/report_detail_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (FCM)
  try {
    if (kIsWeb) {
      debugPrint('Skipping Firebase init on Web (requires firebase_options.dart)');
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase init failed (likely missing config): $e');
  }

  // Local cache (Hive + flutter_secure_storage)
  await LocalCacheService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const DocMedRepoApp(),
    ),
  );
}

class DocMedRepoApp extends StatefulWidget {
  const DocMedRepoApp({super.key});

  @override
  State<DocMedRepoApp> createState() => _DocMedRepoAppState();
}

class _DocMedRepoAppState extends State<DocMedRepoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final notifService = NotificationService.instance;

    // Wire notification taps to navigation
    notifService.setNavigationCallback((type, resourceId) {
      context.read<NotificationProvider>().handleNotification(type, resourceId ?? '');

      final nav = _navigatorKey.currentState;
      if (nav == null) return;

      switch (type) {
        case 'report_ready':
          nav.pushNamedAndRemoveUntil('/patient/dashboard', (_) => false);
          nav.push(MaterialPageRoute(builder: (_) => ReportDetailScreen(reportId: resourceId!)));
          break;
        case 'report_failed':
        case 'new_prescription':
          nav.pushNamedAndRemoveUntil('/patient/dashboard', (_) => false);
          break;
      }
    });

    await notifService.init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey:  _navigatorKey,
      title:         'DocMedRepo',
      debugShowCheckedModeBanner: false,
      theme:         AppTheme.light,
      darkTheme:     AppTheme.dark,
      themeMode:     ThemeMode.system,
      routes: {
        '/':                  (_) => const _RootRouter(),
        '/patient/dashboard': (_) => const PatientDashboardScreen(),
        '/doctor/dashboard':  (_) => const DoctorDashboardScreen(),
      },
    );
  }
}

/// Decides the initial screen based on auth state:
///   - Not initialised → loading spinner
///   - Logged in as patient → PatientDashboard
///   - Logged in as doctor  → DoctorDashboard
///   - Not logged in        → role selection screen
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.initialised) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.isPatient) return const PatientDashboardScreen();
    if (auth.isDoctor)  return const DoctorDashboardScreen();
    return const _RoleSelectionScreen();
  }
}

/// Landing screen letting users choose between Patient and Doctor login.
class _RoleSelectionScreen extends StatelessWidget {
  const _RoleSelectionScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand mark
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.medical_services_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 32),
              Text('DocMedRepo', style: theme.textTheme.displayLarge),
              const SizedBox(height: 8),
              Text(
                'Secure medical records,\nanywhere you need them.',
                style: theme.textTheme.bodyLarge,
              ),
              const Spacer(),

              // Role selection cards
              _RoleCard(
                icon:     Icons.person_outline_rounded,
                title:    'I am a Patient',
                subtitle: 'Access your records, reports & prescriptions',
                color:    theme.colorScheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PatientLoginScreen()),
                ),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon:     Icons.local_hospital_outlined,
                title:    'I am a Doctor',
                subtitle: 'View patient records, write prescriptions',
                color:    theme.colorScheme.secondary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DoctorLoginScreen()),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
