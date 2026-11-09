import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/first_run_setup_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import 'app_shell.dart';

class SupermarketApp extends StatelessWidget {
  const SupermarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supermarket',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootGate(),
    );
  }
}

/// Decides what to show: app, login, or first-run setup.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Signed in? Go straight to the app, no need to hit the database again.
    final user = ref.watch(authControllerProvider);
    if (user != null) return const AppShell();

    final hasUsers = ref.watch(hasUsersProvider);

    return hasUsers.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't open the database."),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(hasUsersProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (exists) =>
          exists ? const LoginScreen() : const FirstRunSetupScreen(),
    );
  }
}