import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/error_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_button.dart';
import 'upload_report_screen.dart';
import 'patient_history_screen.dart';
import 'report_detail_screen.dart';
import 'notification_screen.dart';

class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _prescriptions = [];
  bool _loading = true;
  String? _error;
  String? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool refresh = false}) async {
    // Show cached data immediately
    if (!refresh) {
      final cache = LocalCacheService.instance;
      final cachedProfile = cache.getCachedProfile();
      final cachedReports = cache.getCachedReports();
      final cachedRx      = cache.getCachedPrescriptions();

      if (cachedProfile != null) {
        setState(() {
          _profile       = cachedProfile;
          _reports       = cachedReports ?? [];
          _prescriptions = cachedRx      ?? [];
          _loading       = false;
          _lastUpdated   = cache.getLastUpdatedLabel('profile');
        });
      }
    }

    try {
      final api = ApiService.instance;
      final results = await Future.wait([
        api.getMyProfile(),
        api.getMyReports(),
        api.getMyPrescriptions(),
      ]);

      final profile  = results[0]['patient'] as Map<String, dynamic>;
      final reports  = List<Map<String, dynamic>>.from(
          (results[1]['reports'] as List).map((e) => Map<String, dynamic>.from(e)));
      final rxList   = List<Map<String, dynamic>>.from(
          (results[2]['prescriptions'] as List).map((e) => Map<String, dynamic>.from(e)));

      // Update cache
      final cache = LocalCacheService.instance;
      await Future.wait([
        cache.saveProfile(profile),
        cache.saveReports(reports),
        cache.savePrescriptions(rxList),
      ]);

      if (mounted) {
        setState(() {
          _profile       = profile;
          _reports       = reports;
          _prescriptions = rxList;
          _loading       = false;
          _error         = null;
          _lastUpdated   = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && _profile == null) {
        setState(() { _loading = false; _error = e.message; });
      }
    }
  }

  // ── QR Code modal ─────────────────────────────────────────────────────────
  Future<void> _showQrModal() async {
    try {
      final data = await ApiService.instance.generateQr();
      final token     = data['token'] as String;
      final expiresAt = DateTime.parse(data['expiresAt'] as String);

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _QrBottomSheet(token: token, expiresAt: expiresAt),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  // ── Delete Account modal ──────────────────────────────────────────────────
  Future<void> _showDeleteAccountModal() async {
    final pwdController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This action is irreversible. All your reports, prescriptions, and data will be permanently deleted.'),
            const SizedBox(height: 16),
            TextField(
              controller: pwdController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Verify Password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || pwdController.text.isEmpty) return;
    if (!mounted) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      await ApiService.instance.deleteAccount(pwdController.text);
      if (!mounted) return;
      Navigator.pop(context); // close dialog
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) return Scaffold(body: LoadingSkeleton.dashboard());
    if (_error != null && _profile == null) {
      return Scaffold(
        body: ErrorState(message: _error!, onRetry: () => _loadData(refresh: true)),
      );
    }

    final name = _profile?['name'] as String? ?? 'Patient';
    final todayMeds = _getTodayMedications();

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
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PatientHistoryScreen()),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) async {
              if (val == 'logout') {
                await context.read<AuthProvider>().logout();
                if (mounted) Navigator.pushReplacementNamed(context, '/');
              } else if (val == 'delete') {
                _showDeleteAccountModal();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Logout'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_forever_rounded, color: Colors.red), title: Text('Delete Account', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(refresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_lastUpdated!,
                      style: theme.textTheme.labelSmall?.copyWith(color: Colors.orange[400])),
                ),
              Text('Good ${_greeting()},', style: theme.textTheme.bodyMedium),
              Text(name, style: theme.textTheme.displayMedium),
              const SizedBox(height: 24),

              // Quick actions
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'My QR Code',
                      icon: Icons.qr_code_rounded,
                      variant: AppButtonVariant.primary,
                      onPressed: _showQrModal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: 'Upload Report',
                      icon: Icons.upload_rounded,
                      variant: AppButtonVariant.outline,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UploadReportScreen()),
                      ).then((_) => _loadData(refresh: true)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Today's medications
              if (todayMeds.isNotEmpty) ...[
                _SectionHeader(title: "Today's Medications", icon: Icons.medication_rounded),
                const SizedBox(height: 12),
                ...todayMeds.map((med) => _MedCard(med: med)),
                const SizedBox(height: 24),
              ],

              // Recent reports
              _SectionHeader(title: 'Recent Reports', icon: Icons.description_outlined),
              const SizedBox(height: 12),
              if (_reports.isEmpty)
                EmptyState(
                  icon: Icons.description_outlined,
                  title: 'No reports yet',
                  message: 'Upload your first medical report to get started.',
                )
              else
                ..._reports.take(3).map((r) => _ReportCard(report: r)),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  List<Map<String, dynamic>> _getTodayMedications() {
    final meds = <Map<String, dynamic>>[];
    for (final rx in _prescriptions) {
      final rxMeds = rx['medications'] as List? ?? [];
      for (final med in rxMeds) {
        meds.add(Map<String, dynamic>.from(med as Map));
      }
    }
    return meds.take(5).toList();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _MedCard extends StatelessWidget {
  final Map<String, dynamic> med;
  const _MedCard({required this.med});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.medication, color: theme.colorScheme.secondary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(med['name'] as String? ?? '',
                      style: theme.textTheme.titleSmall),
                  Text(
                    '${med['dosage'] ?? ''} · ${med['frequency'] ?? ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final status = report['analysisStatus'] as String? ?? 'pending';
    final color  = _statusColor(status, theme);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportDetailScreen(reportId: report['_id'] as String),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.description_outlined, color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report['description'] as String? ?? 'Medical Report',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(report['fileType']?.toString().toUpperCase() ?? '',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusLabel(status),
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Color _statusColor(String s, ThemeData t) {
    switch (s) {
      case 'complete':   return Colors.green;
      case 'processing': return Colors.orange;
      case 'failed':     return t.colorScheme.error;
      default:           return Colors.grey;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'complete':   return 'Ready';
      case 'processing': return 'Analysing';
      case 'failed':     return 'Failed';
      default:           return 'Pending';
    }
  }
}

/// QR code bottom sheet with countdown timer and auto-refresh.
class _QrBottomSheet extends StatefulWidget {
  final String token;
  final DateTime expiresAt;
  const _QrBottomSheet({required this.token, required this.expiresAt});

  @override
  State<_QrBottomSheet> createState() => _QrBottomSheetState();
}

class _QrBottomSheetState extends State<_QrBottomSheet> {
  late Timer _timer;
  late Duration _remaining;
  late String _currentToken;
  late DateTime _currentExpiry;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _currentToken  = widget.token;
    _currentExpiry = widget.expiresAt;
    _remaining     = _currentExpiry.difference(DateTime.now());
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _currentExpiry.difference(DateTime.now());
      if (left.isNegative) {
        setState(() => _remaining = Duration.zero);
        _timer.cancel();
        _regenerate();
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final data = await ApiService.instance.generateQr();
      _currentToken  = data['token'] as String;
      _currentExpiry = DateTime.parse(data['expiresAt'] as String);
      _startTimer();
    } catch (_) {}
    if (mounted) setState(() => _regenerating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mins  = _remaining.inMinutes.toString().padLeft(2, '0');
    final secs  = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final isExpiring = _remaining.inSeconds < 60;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Your QR Code', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Show this to your doctor to grant access',
              style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (_regenerating)
            const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20)],
              ),
              padding: const EdgeInsets.all(16),
              child: QrImageView(data: _currentToken, size: 200),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, size: 16,
                  color: isExpiring ? Colors.red : theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Expires in $mins:$secs',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontWeight: FontWeight.w600,
                  color: isExpiring ? Colors.red : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
