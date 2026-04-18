import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'doctor_add_prescription_screen.dart';
import 'report_detail_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';

/// Displays a scanned patient's profile to the doctor.
/// Accessible only after a valid QR scan.
class DoctorPatientDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String qrToken;

  const DoctorPatientDetailsScreen({
    super.key,
    required this.patient,
    required this.qrToken,
  });

  @override
  State<DoctorPatientDetailsScreen> createState() => _DoctorPatientDetailsScreenState();
}

class _DoctorPatientDetailsScreenState extends State<DoctorPatientDetailsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _reportsLoaded = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patientId = widget.patient['_id'] as String;
      final data = await ApiService.instance.getPatientReports(patientId, widget.qrToken);
      setState(() {
        _reports = List<Map<String, dynamic>>.from(
            (data['reports'] as List).map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
        _reportsLoaded = true;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patient = widget.patient;
    final name = patient['name'] as String? ?? 'Patient';
    final email = patient['email'] as String? ?? '';
    final blood = patient['bloodGroup'] as String? ?? 'Unknown';
    final allerg = List<String>.from(patient['allergies'] as List? ?? []);
    final diseas = List<String>.from(patient['diseases'] as List? ?? []);
    final ec = patient['emergencyContact'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add Prescription',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorAddPrescriptionScreen(
                  patientId: patient['_id'] as String,
                  patientName: name,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Text(
                        name[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(email, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    _BloodGroupBadge(group: blood),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Allergies
            _InfoSection(
              title: 'Allergies',
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange,
              content: allerg.isEmpty
                  ? [const Text('None recorded')]
                  : allerg.map((a) => _Chip(label: a, color: Colors.orange)).toList(),
            ),
            const SizedBox(height: 12),

            // Diseases / Conditions
            _InfoSection(
              title: 'Medical Conditions',
              icon: Icons.medical_information_outlined,
              iconColor: theme.colorScheme.primary,
              content: diseas.isEmpty
                  ? [const Text('None recorded')]
                  : diseas.map((d) => _Chip(label: d, color: theme.colorScheme.primary)).toList(),
            ),
            const SizedBox(height: 12),

            // Emergency contact
            if (ec != null)
              _InfoSection(
                title: 'Emergency Contact',
                icon: Icons.emergency_outlined,
                iconColor: theme.colorScheme.error,
                content: [
                  Text('${ec['name']} (${ec['relation']})', style: theme.textTheme.bodyMedium),
                  Text(ec['phone'] as String? ?? '', style: theme.textTheme.bodySmall),
                ],
              ),

            const SizedBox(height: 24),

            // Patient Reports
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Text('Patient Reports', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),

            if (!_reportsLoaded && !_loading)
              ElevatedButton.icon(
                onPressed: _loadReports,
                icon: const Icon(Icons.visibility),
                label: const Text('View Reports'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )
            else if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorState(message: _error!, onRetry: _loadReports)
            else if (_reports.isEmpty)
              const EmptyState(
                icon: Icons.description_outlined,
                title: 'No reports',
                message: 'This patient has not uploaded any reports.',
              )
            else
              ..._reports.map((r) => _ReportTile(report: r, isDoctorView: true, qrToken: widget.qrToken)),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorAddPrescriptionScreen(
                    patientId: patient['_id'] as String,
                    patientName: name,
                  ),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Write Prescription'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool isDoctorView;
  final String? qrToken;

  const _ReportTile({required this.report, this.isDoctorView = false, this.qrToken});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = report['analysisStatus'] as String? ?? 'pending';

    Color statusColor;
    if (status == 'complete') statusColor = Colors.green;
    else if (status == 'failed') statusColor = theme.colorScheme.error;
    else if (status == 'processing') statusColor = Colors.orange;
    else statusColor = Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.description_outlined, color: theme.colorScheme.secondary),
        title: Text(report['description'] as String? ?? 'Medical Report',
            style: theme.textTheme.titleSmall),
        subtitle: Text('${(report['fileType'] as String? ?? '').toUpperCase()} · $status'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status.toUpperCase(),
            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportDetailScreen(
                reportId: report['_id'] as String,
                isDoctorView: isDoctorView,
                qrToken: qrToken,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> content;

  const _InfoSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: content),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      );
}

class _BloodGroupBadge extends StatelessWidget {
  final String group;
  const _BloodGroupBadge({required this.group});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(group,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            )),
      );
}
