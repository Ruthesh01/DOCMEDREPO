import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

class PrescriptionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> prescription;
  final bool isDoctorView;

  const PrescriptionDetailScreen({
    super.key,
    required this.prescription,
    this.isDoctorView = false,
  });

  @override
  State<PrescriptionDetailScreen> createState() => _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState extends State<PrescriptionDetailScreen> {
  bool _cancelling = false;

  Future<void> _cancelPrescription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel Prescription?'),
        content: const Text('This will hide the prescription from the patient.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _cancelling = true);
    try {
      await ApiService.instance.cancelPrescription(widget.prescription['_id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prescription cancelled successfully')),
      );
      Navigator.pop(context, true); // return true to indicate refresh needed
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prescription = widget.prescription;
    final doctor = prescription['doctorId'] as Map<String, dynamic>?;
    final patient = prescription['patientId'] as Map<String, dynamic>?;
    final meds = prescription['medications'] as List? ?? [];
    final notes = prescription['notes'] as String?;
    final isActive = prescription['active'] as bool? ?? true;
    
    DateTime? createdAt;
    if (prescription['createdAt'] != null) {
      createdAt = DateTime.tryParse(prescription['createdAt'] as String);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription Details'),
        actions: [
          if (widget.isDoctorView && isActive)
            _cancelling
                ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                    tooltip: 'Cancel Prescription',
                    onPressed: _cancelPrescription,
                  ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isActive)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text('This prescription has been cancelled.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            widget.isDoctorView && patient != null
                ? _buildPatientCard(theme, patient, createdAt)
                : _buildDoctorCard(theme, doctor, createdAt),
            const SizedBox(height: 24),
            Text('Medications', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...meds.map((m) => _buildMedicationCard(theme, Map<String, dynamic>.from(m as Map))),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Doctor\'s Notes', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.yellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellow.withOpacity(0.4)),
                ),
                child: Text(notes, style: theme.textTheme.bodyMedium),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(ThemeData theme, Map<String, dynamic> patient, DateTime? date) {
    return Container(
      padding: const EdgeInsets.all(20),
      // ... similar style
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.secondary.withOpacity(0.1),
                child: Text(
                  (patient['name'] as String? ?? '?')[0].toUpperCase(),
                  style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient['name'] as String? ?? 'Unknown Patient', style: theme.textTheme.titleMedium),
                    Text(patient['email'] as String? ?? '', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (date != null) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Issued on ${DateFormat.yMMMd().format(date)}', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDoctorCard(ThemeData theme, Map<String, dynamic>? doctor, DateTime? date) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Icon(Icons.person_outline, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dr. ${doctor?['name'] ?? 'Unknown'}',
                        style: theme.textTheme.titleMedium),
                    Text(doctor?['specialization'] as String? ?? 'Specialization unavailable',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ),
          if (date != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Issued on ${DateFormat.yMMMd().format(date)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationCard(ThemeData theme, Map<String, dynamic> med) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication, color: theme.colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(med['name'] as String? ?? 'Unknown Medication',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMedDetail(theme, 'Dosage', med['dosage'] as String? ?? '-')),
                Expanded(child: _buildMedDetail(theme, 'Frequency', med['frequency'] as String? ?? '-')),
                Expanded(child: _buildMedDetail(theme, 'Duration', med['duration'] as String? ?? '-')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedDetail(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
