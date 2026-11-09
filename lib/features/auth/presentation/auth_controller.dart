import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_repository.dart';
import '../domain/app_user.dart';

/// Holds the signed-in user. `null` means nobody is signed in.
class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = await ref
        .read(userRepositoryProvider)
        .login(username: username, password: password);
  }

  Future<void> createFirstAdmin({
    required String fullName,
    required String username,
    required String password,
  }) async {
    final user = await ref.read(userRepositoryProvider).createFirstAdmin(
          fullName: fullName,
          username: username,
          password: password,
        );
    state = user; // sign them straight in
    ref.invalidate(hasUsersProvider);
  }

  Future<void> logout() async {
    final user = state;
    state = null;
    if (user != null) {
      await ref.read(userRepositoryProvider).recordLogout(user.id);
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AppUser?>(AuthController.new);

/// Whether any account exists yet. Decides first-run setup vs login.
final hasUsersProvider = FutureProvider<bool>((ref) {
  return ref.watch(userRepositoryProvider).hasAnyUser();
});