import 'package:supermarket/core/security/permissions.dart';
import 'package:supermarket/database/enums.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.lastLoginAt,
  });

  final String id;
  final String username;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final DateTime? lastLoginAt;

  bool can(Permission permission) => Permissions.can(role, permission);

  @override
  bool operator ==(Object other) => other is AppUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}