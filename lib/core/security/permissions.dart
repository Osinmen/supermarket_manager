import 'package:supermarket/core/errors/app_exception.dart';
import 'package:supermarket/database/enums.dart';

enum Permission {
  makeSale,
  viewProducts,
  manageProducts,
  changePrices,
  adjustStock,
  voidSale,
  viewReports,
  manageUsers,
  manageBackups,
}

abstract final class Permissions {
  static const _cashier = {Permission.makeSale, Permission.viewProducts};

  static final Map<UserRole, Set<Permission>> _byRole = {
    UserRole.cashier: _cashier,
    UserRole.manager: {
      ..._cashier,
      Permission.manageProducts,
      Permission.changePrices,
      Permission.adjustStock,
      Permission.voidSale,
      Permission.viewReports,
    },
    UserRole.admin: Permission.values.toSet(),
  };

  static bool can(UserRole role, Permission permission) =>
      _byRole[role]?.contains(permission) ?? false;

  /// Used to enforce rules in code, not just to hide buttons.
  static void require(UserRole role, Permission permission) {
    if (!can(role, permission)) {
      throw const PermissionDeniedException(
        "You don't have permission to do that.",
      );
    }
  }
}