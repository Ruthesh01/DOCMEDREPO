import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';

class DoctorAddPrescriptionScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const DoctorAddPrescriptionScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<DoctorAddPrescriptionScreen> createState() =>
      _DoctorAddPrescriptionScreenState();
}

class _DoctorAddPrescriptionScreenState
    extends State<DoctorAddPrescriptionScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();
  bool  _isLoading = false;
  bool  _submitted = false;
  String? _error;

  final List<_MedEntry> _medications = [_MedEntry()];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_medications.isEmpty) {
      setState(() => _error = 'Add at least one medication.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });

    try {
      await ApiService.instance.createPrescription({
        'patientId':  widget.patientId,
        'notes':      _notesCtrl.text.trim(),
        'medications': _medications.map((m) => m.toJson()).toList(),
      });
      if (mounted) setState(() { _isLoading = false; _submitted = true; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Prescribe for ${widget.patientName}')),
      body: _submitted ? _successView(theme) : _form(theme),
    );
  }

  Widget _form(ThemeData theme) => Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                ),

              Row(
                children: [
                  Icon(Icons.medication_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Medications', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _medications.add(_MedEntry())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ..._medications.asMap().entries.map((e) => _MedCard(
                    index:   e.key,
                    entry:   e.value,
                    onRemove: _medications.length > 1
                        ? () => setState(() => _medications.removeAt(e.key))
                        : null,
                  )),

              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Clinical Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 28),
              AppButton(
                label: 'Submit Prescription',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      );

  Widget _successView(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF059669), size: 40),
              ),
              const SizedBox(height: 20),
              Text('Prescription Submitted', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'The prescription has been saved and the patient will be notified.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              AppButton(
                label: 'Done',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }
}

// ── Medication entry model ────────────────────────────────────────────────────
class _MedEntry {
  final nameCtrl      = TextEditingController();
  final dosageCtrl    = TextEditingController();
  final frequencyCtrl = TextEditingController();
  final durationCtrl  = TextEditingController();

  Map<String, String> toJson() => {
        'name':      nameCtrl.text.trim(),
        'dosage':    dosageCtrl.text.trim(),
        'frequency': frequencyCtrl.text.trim(),
        'duration':  durationCtrl.text.trim(),
      };
}

class _MedCard extends StatelessWidget {
  final int       index;
  final _MedEntry entry;
  final VoidCallback? onRemove;

  const _MedCard({
    required this.index,
    required this.entry,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Medication ${index + 1}', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: theme.colorScheme.error,
                    onPressed: onRemove,
                    tooltip: 'Remove',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: entry.nameCtrl,
              decoration: const InputDecoration(labelText: 'Drug Name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.dosageCtrl,
                    decoration: const InputDecoration(labelText: 'Dosage'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: entry.frequencyCtrl,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: entry.durationCtrl,
              decoration: const InputDecoration(labelText: 'Duration (e.g. 7 days)'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
          ],
        ),
      ),
    );
  }
}
