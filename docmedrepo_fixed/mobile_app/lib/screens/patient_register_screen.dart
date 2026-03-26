import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_button.dart';
import 'patient_dashboard_screen.dart';

class PatientRegisterScreen extends StatefulWidget {
  const PatientRegisterScreen({super.key});

  @override
  State<PatientRegisterScreen> createState() => _PatientRegisterScreenState();
}

class _PatientRegisterScreenState extends State<PatientRegisterScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _ecNameCtrl   = TextEditingController();  // emergency contact
  final _ecPhoneCtrl  = TextEditingController();
  final _ecRelCtrl    = TextEditingController();
  bool _obscure       = true;
  bool _isLoading     = false;
  String? _error;
  String? _bloodGroup;

  static const _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });

    final err = await context.read<AuthProvider>().registerPatient(
      name:      _nameCtrl.text.trim(),
      email:     _emailCtrl.text.trim(),
      password:  _passCtrl.text,
      bloodGroup: _bloodGroup,
      emergencyContact: {
        'name':     _ecNameCtrl.text.trim(),
        'phone':    _ecPhoneCtrl.text.trim(),
        'relation': _ecRelCtrl.text.trim(),
      },
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (err != null) { setState(() => _error = err); return; }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PatientDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patient Registration', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Create your secure medical account',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),

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

              // ── Personal info ────────────────────────────────────────────
              _sectionLabel('Personal Information', theme),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Name must be at least 2 characters' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 8)
                    ? 'Password must be at least 8 characters' : null,
              ),
              const SizedBox(height: 14),

              // Blood group dropdown
              DropdownButtonFormField<String>(
                value: _bloodGroup,
                decoration: const InputDecoration(
                  labelText: 'Blood Group (optional)',
                  prefixIcon: Icon(Icons.bloodtype_outlined),
                ),
                items: _bloodGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => _bloodGroup = v),
              ),

              const SizedBox(height: 28),
              _sectionLabel('Emergency Contact', theme),
              const SizedBox(height: 12),

              TextFormField(
                controller: _ecNameCtrl,
                decoration: const InputDecoration(labelText: 'Contact Name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _ecPhoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (10 digits)',
                  prefixIcon: Icon(Icons.phone_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) return 'Enter a valid 10-digit number';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _ecRelCtrl,
                decoration: const InputDecoration(labelText: 'Relation (e.g. Spouse)', prefixIcon: Icon(Icons.family_restroom)),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),

              const SizedBox(height: 32),
              AppButton(
                label: 'Create Account',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeData theme) => Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      );

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _ecNameCtrl, _ecPhoneCtrl, _ecRelCtrl]) {
      c.dispose();
    }
    super.dispose();
  }
}
