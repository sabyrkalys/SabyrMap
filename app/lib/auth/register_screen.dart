import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(authControllerProvider.notifier).clearError();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthAuthenticated && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    final state = ref.watch(authControllerProvider);
    final isLoading = state is AuthAuthenticating;
    final errorMessage = state is AuthUnauthenticated ? state.errorMessage : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('register_email_field'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('register_password_field'),
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ElevatedButton(
              onPressed: isLoading || !_canSubmit
                  ? null
                  : () => ref.read(authControllerProvider.notifier).register(
                        _emailController.text,
                        _passwordController.text,
                      ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
