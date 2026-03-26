import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_button.dart';
import 'doctor_register_screen.dart';
import 'doctor_dashboard_screen.dart';

class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});

  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen> {
  // Step 1: credentials; Step 2: OTP
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  // OTP step
  final List<TextEditingController> _otpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  bool _obscure     = true;
  bool _isLoading   = false;
  bool _showOtp     = false;
  String? _doctorId;
  String? _error;

  Future<void> _submitCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });

    final auth   = context.read<AuthProvider>();
    final result = await auth.loginDoctorStep1(
      email:    _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error'] as String);
      return;
    }

    if (result['completed'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DoctorDashboardScreen()),
      );
      return;
    }

    setState(() {
      _showOtp  = true;
      _doctorId = result['doctorId'] as String?;
    });

    if (result['devOtp'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('DEV MODE: Your OTP is ${result["devOtp"]}'),
          duration: const Duration(seconds: 10),
          backgroundColor: Colors.blue.shade800,
        ),
      );
    }
  }

  Future<void> _submitOtp() async {
    final otp = _otpCtrl.map((c) => c.text).join();
    if (otp.length < 6) {
      setState(() => _error = 'Please enter all 6 digits');
      return;
    }
    if (_doctorId == null) return;

    setState(() { _isLoading = true; _error = null; });

    final auth = context.read<AuthProvider>();
    final err  = await auth.loginDoctorStep2(doctorId: _doctorId!, otp: otp);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (err != null) { setState(() => _error = err); return; }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DoctorDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 28),
              Text(_showOtp ? 'Verify Identity' : 'Doctor Login',
                  style: theme.textTheme.displayMedium),
              const SizedBox(height: 6),
              Text(
                _showOtp
                    ? 'Enter the 6-digit code sent to your email'
                    : 'Sign in to your doctor account',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 36),

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

              if (!_showOtp) _credentialsForm(theme) else _otpForm(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credentialsForm(ThemeData theme) => Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
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
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 28),
            AppButton(
              label: 'Continue',
              isLoading: _isLoading,
              onPressed: _submitCredentials,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("New doctor? ", style: theme.textTheme.bodyMedium),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DoctorRegisterScreen())),
                  child: Text('Register',
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'DMSans',
                      )),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _otpForm(ThemeData theme) => Column(
        children: [
          // 6-box OTP input
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) => _OtpBox(
              controller: _otpCtrl[i],
              focusNode:  _otpFocus[i],
              onChanged: (v) {
                if (v.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
                if (v.isEmpty && i > 0)   _otpFocus[i - 1].requestFocus();
              },
            )),
          ),
          const SizedBox(height: 28),
          AppButton(
            label: 'Verify OTP',
            isLoading: _isLoading,
            onPressed: _submitOtp,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() { _showOtp = false; _error = null; }),
            child: const Text('← Back to login'),
          ),
        ],
      );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    for (final c in _otpCtrl) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 46,
      child: TextFormField(
        controller:  controller,
        focusNode:   focusNode,
        keyboardType: TextInputType.number,
        textAlign:   TextAlign.center,
        maxLength:   1,
        onChanged:   onChanged,
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.outline.withOpacity(0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
        ),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
    );
  }
}
