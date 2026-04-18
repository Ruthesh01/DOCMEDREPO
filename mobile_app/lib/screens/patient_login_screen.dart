import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/biometric_service.dart';
import '../widgets/app_button.dart';
import 'patient_register_screen.dart';
import 'patient_dashboard_screen.dart';

class PatientLoginScreen extends StatefulWidget {
  const PatientLoginScreen({super.key});

  @override
  State<PatientLoginScreen> createState() => _PatientLoginScreenState();
}

class _PatientLoginScreenState extends State<PatientLoginScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  bool _obscure     = true;
  bool _isLoading   = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tryBiometricAutoLogin();
  }

  /// If biometric is enabled, attempt silent login on app open.
  Future<void> _tryBiometricAutoLogin() async {
    final bio = BiometricService.instance;
    if (!bio.isEnabled()) return;
    if (!await bio.isAvailable()) return;

    final authenticated = await bio.authenticate(
      reason: 'Use biometrics to access your medical records',
    );
    if (!mounted || !authenticated) return;

    final auth = context.read<AuthProvider>();
    final ok   = await auth.biometricLogin();
    if (ok && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientDashboardScreen()),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });

    final auth = context.read<AuthProvider>();
    final err  = await auth.loginPatient(
      email:    _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (err != null) {
      setState(() => _error = err);
      return;
    }

    // Offer biometric enrolment on first login
    await _offerBiometric();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PatientDashboardScreen()),
    );
  }

  Future<void> _offerBiometric() async {
    final bio = BiometricService.instance;
    if (bio.isEnabled()) return;
    if (!await bio.isAvailable()) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable Biometric Login?'),
        content: const Text(
          'Use your fingerprint or Face ID to log in faster next time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('Enable')),
        ],
      ),
    );
    if (enable == true) await bio.enable();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // Logo / brand
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 28),
                Text('Welcome back', style: theme.textTheme.displayMedium),
                const SizedBox(height: 6),
                Text('Sign in to your patient account',
                    style: theme.textTheme.bodyLarge),

                const SizedBox(height: 36),

                // Error banner
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

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
                  validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                ),

                const SizedBox(height: 28),

                AppButton(
                  label: 'Sign In',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account? ", style: theme.textTheme.bodyMedium),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PatientRegisterScreen()),
                      ),
                      child: Text(
                        'Sign up',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'DMSans',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
