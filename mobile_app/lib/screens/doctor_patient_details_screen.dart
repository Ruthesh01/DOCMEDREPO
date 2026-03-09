import 'package:flutter/material.dart';
import 'doctor_add_prescription_screen.dart';

/// Displays a scanned patient's profile to the doctor.
/// Accessible only after a valid QR scan.
class DoctorPatientDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> patient;
  const DoctorPatientDetailsScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final name   = patient['name'] as String? ?? 'Patient';
    final email  = patient['email'] as String? ?? '';
    final blood  = patient['bloodGroup'] as String? ?? 'Unknown';
    final allerg = List<String>.from(patient['allergies'] as List? ?? []);
    final diseas = List<String>.from(patient['diseases'] as List? ?? []);
    final ec     = patient['emergencyContact'] as Map<String, dynamic>?;

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
                  patientId:   patient['_id'] as String,
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
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
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
                  Text('${ec['name']} (${ec['relation']})',
                      style: theme.textTheme.bodyMedium),
                  Text(ec['phone'] as String? ?? '',
                      style: theme.textTheme.bodySmall),
                ],
              ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorAddPrescriptionScreen(
                    patientId:   patient['_id'] as String,
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
          ],
        ),
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
          color: color.withOpacity(0.1),
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
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Text(group,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            )),
      );
}
