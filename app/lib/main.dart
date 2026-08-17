import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'map/map_screen.dart';

void main() {
  runApp(const ProviderScope(child: AlpineQuestApp()));
}

class AlpineQuestApp extends StatelessWidget {
  const AlpineQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlpineQuest',
      home: const AuthGate(),
      routes: {
        '/register': (context) => const RegisterScreen(),
      },
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return switch (state) {
      AuthAuthenticated() => const MapScreen(),
      AuthAuthenticating() => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthUnauthenticated() => const LoginScreen(),
    };
  }
}
