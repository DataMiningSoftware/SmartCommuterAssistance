import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/app_logo.dart';

class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _loading = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _authService.signInWithOtp(phone);
      if (mounted) setState(() => _codeSent = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatDatabaseException(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final token = _codeController.text.trim();
    if (token.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _authService.verifyOtp(
        phone: _phoneController.text.trim(),
        token: token,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatDatabaseException(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with phone')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppLogo(size: 64),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+60 12-345 6789',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_codeSent)
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loading
                        ? null
                        : (_codeSent ? _verify : _sendCode),
                    child: Text(
                      _loading
                          ? 'Please wait…'
                          : (_codeSent ? 'Verify code' : 'Send code'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A one-time code will be sent by SMS. Requires the Phone '
                    'provider to be enabled in Supabase.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
