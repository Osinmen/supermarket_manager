import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/password_hasher.dart';
import 'auth_controller.dart';
import 'auth_layout.dart';

class FirstRunSetupScreen extends ConsumerStatefulWidget {
  const FirstRunSetupScreen({super.key});

  @override
  ConsumerState<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9._]{3,40}$');

  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).createFirstAdmin(
            fullName: _fullName.text,
            username: _username.text,
            password: _password.text,
          );
      // Signed in automatically; the root gate moves on to the app.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Set up your store',
      subtitle: 'Create the admin account. You can add staff later.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              AuthErrorBox(_error!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _fullName,
              autofocus: true,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Enter your full name';
                if (value.length > 80) return 'At most 80 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _username,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
                helperText: 'Letters, numbers, dot or underscore',
              ),
              validator: (v) => _usernamePattern.hasMatch(v?.trim() ?? '')
                  ? null
                  : '3 to 40 characters: letters, numbers, . or _',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => PasswordHasher.validate(v ?? ''),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (v) =>
                  v == _password.text ? null : "Passwords don't match",
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create admin account'),
            ),
          ],
        ),
      ),
    );
  }
}