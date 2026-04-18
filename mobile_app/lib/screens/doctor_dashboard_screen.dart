import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/error_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_button.dart';
import 'doctor_patient_details_screen.dart';
import 'notification_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  Map<String, dynamic>? _doctor;
  List<Map<String, dynamic>> _prescriptions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.instance.getDoctorProfile(),
        ApiService.instance.getDoctorPrescriptions(),
      ]);
      setState(() {
        _doctor        = results[0]['doctor'] as Map<String, dynamic>;
        _prescriptions = List<Map<String, dynamic>>.from(
            (results[1]['prescriptions'] as List).map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  /// Opens the camera scanner to read a patient QR code.
  Future<void> _scanQr() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (token == null || !mounted) return;

    try {
      final data = await ApiService.instance.scanQr(token);
      final patient = data['patient'] as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DoctorPatientDetailsScreen(patient: patient, qrToken: token),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  int get _todayCount {
    final today = DateTime.now();
    return _prescriptions.where((rx) {
      final created = DateTime.tryParse(rx['createdAt'] as String? ?? '');
      if (created == null) return false;
      return created.year == today.year &&
             created.month == today.month &&
             created.day == today.day;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) return Scaffold(body: LoadingSkeleton.dashboard());
    if (_error != null && _doctor == null) {
      return Scaffold(body: ErrorState(message: _error!, onRetry: _load));
    }

    final name = _doctor?['name'] as String? ?? 'Doctor';
    final spec = _doctor?['specialization'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('DocMedRepo'),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, notif, child) {
              return IconButton(
                icon: Badge(
                  isLabelVisible: notif.unreadCount > 0,
                  label: Text('${notif.unreadCount}'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
                onPressed: () {
                  notif.markAsRead();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationScreen()),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              Text('Dr. $name', style: theme.textTheme.displayMedium),
              Text(spec, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),

              // Scan QR button
              AppButton(
                label: 'Scan Patient QR',
                icon: Icons.qr_code_scanner_rounded,
                onPressed: _scanQr,
              ),
              const SizedBox(height: 24),

              // Stats row
              Row(
                children: [
                  _StatCard(
                    icon: Icons.assignment_outlined,
                    label: "Today's Prescriptions",
                    value: _todayCount.toString(),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.people_outline,
                    label: 'Total Patients',
                    value: _prescriptions
                        .map((rx) => rx['patientId'])
                        .toSet()
                        .length
                        .toString(),
                    color: theme.colorScheme.secondary,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Recent prescriptions
              Row(
                children: [
                  Icon(Icons.medication_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Recent Prescriptions', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),

              if (_prescriptions.isEmpty)
                const EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'No prescriptions yet',
                  message: 'Prescriptions you write will appear here.',
                )
              else
                ..._prescriptions.take(5).map((rx) => _PrescriptionTile(rx: rx)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                  fontFamily: 'Merriweather',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: color,
                )),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionTile extends StatelessWidget {
  final Map<String, dynamic> rx;
  const _PrescriptionTile({required this.rx});

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final patient = rx['patientId'] as Map<String, dynamic>?;
    final meds    = rx['medications'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.12),
          child: Text(
            (patient?['name'] as String? ?? '?')[0].toUpperCase(),
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(patient?['name'] as String? ?? 'Patient',
            style: theme.textTheme.titleSmall),
        subtitle: Text('${meds.length} medication${meds.length == 1 ? '' : 's'}'),
      ),
    );
  }
}

/// Full-screen QR scanner. Returns the scanned token string.
class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Patient QR')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              final value   = barcode?.rawValue;
              if (value != null && value.isNotEmpty) {
                _scanned = true;
                Navigator.pop(context, value);
              }
            },
          ),
          // Scan overlay
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0, right: 0,
            child: Text(
              'Point the camera at the patient\'s QR code',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontFamily: 'DMSans'),
            ),
          ),
        ],
      ),
    );
  }
}
