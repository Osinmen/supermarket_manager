import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supermarket/core/security/permissions.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/password_hasher.dart';
import '../../../database/app_database.dart';
import '../../../database/audit_logger.dart';
import '../../../database/database_provider.dart';
import '../../../database/enums.dart';
import '../domain/app_user.dart';

class UserRepository {
  UserRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditLogger _audit;

  static final _usernamePattern = RegExp(r'^[a-z0-9._]{3,40}$');

  /// True once at least one account exists. Decides first-run vs login.
  Future<bool> hasAnyUser() async {
    final count = _db.users.id.count();
    final row = await (_db.selectOnly(
      _db.users,
    )..addColumns([count])).getSingle();
    return (row.read(count) ?? 0) > 0;
  }
  // ---------------------------------------------------------- user admin

  /// A live list for the Users screen.
  Stream<List<AppUser>> watchAll() {
    return (_db.select(_db.users)
          ..orderBy([(u) => OrderingTerm.asc(u.fullName)]))
        .watch()
        .map((rows) => rows.map((r) => _toAppUser(r)).toList());
  }

  Future<AppUser> createUser({
    required AppUser actor,
    required String fullName,
    required String username,
    required String password,
    required UserRole role,
  }) async {
    Permissions.require(actor.role, Permission.manageUsers);

    final cleanName = _validateFullName(fullName);
    final cleanUsername = _validateUsername(username);
    final passwordProblem = PasswordHasher.validate(password);
    if (passwordProblem != null) throw ValidationException(passwordProblem);

    final hash = await PasswordHasher.hash(password);

    return _db.transaction(() async {
      final clash = await (_db.select(_db.users)
            ..where((u) => u.username.equals(cleanUsername)))
          .getSingleOrNull();
      if (clash != null) {
        throw DuplicateException(
          'Username "$cleanUsername" is already taken.',
        );
      }

      final row = await _db.into(_db.users).insertReturning(
            UsersCompanion.insert(
              username: cleanUsername,
              fullName: cleanName,
              passwordHash: hash,
              role: role,
            ),
          );

      await _audit.log(
        userId: actor.id,
        action: 'user.created',
        details: 'username=$cleanUsername role=${role.name}',
      );
      return _toAppUser(row);
    });
  }

  Future<void> changeRole({
    required AppUser actor,
    required String userId,
    required UserRole role,
  }) async {
    Permissions.require(actor.role, Permission.manageUsers);

    if (userId == actor.id) {
      throw const ValidationException("You can't change your own role.");
    }

    await _db.transaction(() async {
      final user = await _getOrThrow(userId);
      if (user.role == role) return;

      if (user.role == UserRole.admin) {
        await _ensureAnotherActiveAdmin(excludingId: userId);
      }

      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(role: Value(role), updatedAt: Value(DateTime.now())),
      );

      await _audit.log(
        userId: actor.id,
        action: 'user.role_changed',
        details: 'id=$userId ${user.role.name} -> ${role.name}',
      );
    });
  }

  /// Accounts are disabled, never deleted: sales and audit logs point to them.
  Future<void> setActive({
    required AppUser actor,
    required String userId,
    required bool isActive,
  }) async {
    Permissions.require(actor.role, Permission.manageUsers);

    if (!isActive && userId == actor.id) {
      throw const ValidationException("You can't disable your own account.");
    }

    await _db.transaction(() async {
      final user = await _getOrThrow(userId);

      if (!isActive && user.role == UserRole.admin) {
        await _ensureAnotherActiveAdmin(excludingId: userId);
      }

      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          isActive: Value(isActive),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _audit.log(
        userId: actor.id,
        action: isActive ? 'user.enabled' : 'user.disabled',
        details: 'id=$userId username=${user.username}',
      );
    });
  }

  Future<void> resetPassword({
    required AppUser actor,
    required String userId,
    required String newPassword,
  }) async {
    Permissions.require(actor.role, Permission.manageUsers);

    final problem = PasswordHasher.validate(newPassword);
    if (problem != null) throw ValidationException(problem);

    final hash = await PasswordHasher.hash(newPassword);

    await _db.transaction(() async {
      final user = await _getOrThrow(userId);

      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          passwordHash: Value(hash),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _audit.log(
        userId: actor.id,
        action: 'user.password_reset',
        details: 'id=$userId username=${user.username}',
      );
    });
  }

  Future<User> _getOrThrow(String id) async {
    final row = await (_db.select(_db.users)..where((u) => u.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw const NotFoundException('User not found.');
    return row;
  }

  /// Stops the app from ending up with no one who can manage users.
  Future<void> _ensureAnotherActiveAdmin({required String excludingId}) async {
    final count = _db.users.id.count();
    final query = _db.selectOnly(_db.users)
      ..addColumns([count])
      ..where(
        _db.users.role.equalsValue(UserRole.admin) &
            _db.users.isActive.equals(true) &
            _db.users.id.equals(excludingId).not(),
      );
    final others = await query.map((row) => row.read(count)).getSingle();

    if ((others ?? 0) == 0) {
      throw const ValidationException(
        'There must be at least one active admin.',
      );
    }
  }
  /// Creates the very first account, always an admin. Refuses to run if any
  /// user already exists, so it can't be used to sneak in a second admin.
  Future<AppUser> createFirstAdmin({
    required String fullName,
    required String username,
    required String password,
  }) async {
    final cleanName = _validateFullName(fullName);
    final cleanUsername = _validateUsername(username);
    final passwordProblem = PasswordHasher.validate(password);
    if (passwordProblem != null) throw ValidationException(passwordProblem);

    // Hash outside the transaction: bcrypt is slow and shouldn't hold the
    // database lock.
    final hash = await PasswordHasher.hash(password);

    return _db.transaction(() async {
      if (await hasAnyUser()) {
        throw const PermissionDeniedException(
          'Setup has already been completed.',
        );
      }
      final row = await _db
          .into(_db.users)
          .insertReturning(
            UsersCompanion.insert(
              username: cleanUsername,
              fullName: cleanName,
              passwordHash: hash,
              role: UserRole.admin,
              lastLoginAt: Value(DateTime.now()),
            ),
          );
      await _audit.log(
        userId: row.id,
        action: 'user.first_admin_created',
        details: 'username=$cleanUsername',
      );
      return _toAppUser(row);
    });
  }

  Future<AppUser> login({
    required String username,
    required String password,
  }) async {
    // One message for "no such user" and "wrong password", so the screen
    // never reveals which usernames exist.
    const failure = AuthException('Wrong username or password.');
    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.isEmpty || password.isEmpty) throw failure;

    final row = await (_db.select(
      _db.users,
    )..where((u) => u.username.equals(cleanUsername))).getSingleOrNull();
    if (row == null) {
      await _audit.log(
        action: 'auth.login_failed',
        details: 'username=$cleanUsername',
      );
      throw failure;
    }
    final ok = await PasswordHasher.verify(password, row.passwordHash);
    if (!ok) {
      await _audit.log(
        userId: row.id,
        action: 'auth.login_failed',
        details: 'wrong password',
      );
      throw failure;
    }
    // Checked after the password so a stranger can't probe which accounts
    // are disabled.
    if (!row.isActive) {
      throw const AuthException(
        'This account is disabled. Ask an admin for help.',
      );
    }
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.users)..where((u) => u.id.equals(row.id))).write(
        UsersCompanion(lastLoginAt: Value(now)),
      );
      await _audit.log(userId: row.id, action: 'auth.login');
    });
    return _toAppUser(row, lastLoginAt: now);
  }

  Future<void> recordLogout(String userId) {
    return _audit.log(userId: userId, action: 'auth.logout');
  }
  // ------------------------------------------------------------ internals
  AppUser _toAppUser(User row, {DateTime? lastLoginAt}) {
    return AppUser(
      id: row.id,
      username: row.username,
      fullName: row.fullName,
      role: row.role,
      isActive: row.isActive,
      lastLoginAt: lastLoginAt ?? row.lastLoginAt,
    );
  }
  String _validateFullName(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > 80) {
      throw const ValidationException('Full name must be 1 to 80 characters.');
    }
    return value;
  }

  String _validateUsername(String input) {
    final value = input.trim().toLowerCase();
    if (!_usernamePattern.hasMatch(value)) {
      throw const ValidationException(
        'Username must be 3 to 40 characters: letters, numbers, dot or '
        'underscore only.',
      );
    }
    return value;
  }

  
}
final usersProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(userRepositoryProvider).watchAll();
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(
    ref.watch(databaseProvider),
    ref.watch(auditLoggerProvider),
  );
});
