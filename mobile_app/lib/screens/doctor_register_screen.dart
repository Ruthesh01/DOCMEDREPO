import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_button.dart';
import 'doctor_login_screen.dart';

class DoctorRegisterScreen extends StatefulWidget {
  const DoctorRegisterScreen({super.key});

  @override
  State<DoctorRegisterScreen> createState() => _DoctorRegisterScreenState();
}

class _DoctorRegisterScreenState extends State<DoctorRegisterScreen> {
  final _formKey          = GlobalKey<FormState>();
  final _nameCtrl         = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _passCtrl         = TextEditingController();
  final _specCtrl         = TextEditingController();
  final _licenseCtrl      = TextEditingController();
  bool  _obscure          = true;
  bool  _isLoading        = false;
  String? _error;
  String? _success;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; _success = null; });

    final err = await context.read<AuthProvider>().registerDoctor(
      name:          _nameCtrl.text.trim(),
      email:         _emailCtrl.text.trim(),
      password:      _passCtrl.text,
      specialization: _specCtrl.text.trim(),
      licenseNumber:  _licenseCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (err != null) { setState(() => _error = err); return; }

    setState(() => _success = 'Account created! Please log in to continue.');
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DoctorLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create Doctor Account', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('All fields are required', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),

              if (_error != null)
                _banner(_error!, isError: true, theme: theme),
              if (_success != null)
                _banner(_success!, isError: false, theme: theme),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
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
                    ? 'Minimum 8 characters' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _specCtrl,
                decoration: const InputDecoration(
                  labelText: 'Specialization',
                  prefixIcon: Icon(Icons.medical_information_outlined),
                  hintText: 'e.g. Cardiology, Neurology',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _licenseCtrl,
                decoration: const InputDecoration(
                  labelText: 'Medical License Number',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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

  Widget _banner(String msg, {required bool isError, required ThemeData theme}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? theme.colorScheme.errorContainer
              : const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          msg,
          style: TextStyle(
            color: isError ? theme.colorScheme.error : const Color(0xFF059669),
            fontSize: 13,
          ),
        ),
      );

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _specCtrl, _licenseCtrl]) {
      c.dispose();
    }
    super.dispose();
  }
}
