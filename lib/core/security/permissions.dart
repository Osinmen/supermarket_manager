import 'package:supermarket/core/errors/app_exception.dart';

enum Permission {
  makeSale,
  viewProducts,
  manaegeProducts,
  changePrices,
  adjustStock,
  voidSale,
  viewReports,
  manageUsers,
  manageBackups,
}

enum UserRole { admin, cashier, manager }

abstract final class Persmissions {
  static const _cashier = {Permission.makeSale, Permission.viewProducts};
  static final Map<UserRole, Set<Permission>> _byRole = {
    UserRole.cashier: _cashier,
    UserRole.manager: {
      ..._cashier,
      Permission.manaegeProducts,
      Permission.changePrices,
      Permission.adjustStock,
      Permission.voidSale,
      Permission.viewReports,
    },

    //these are used to enforce rules not just to hide buttons.
    UserRole.admin: Permission.values.toSet(),
  };
  static bool can(UserRole role, Permission permission) =>
      _byRole[role]?.contains(permission) ?? false;

  static void require(UserRole role, Permission permission) {
    if (!can(role, permission)) {
      throw const PermissionDeniedException(
        "you dont have the permission to do that.",
      );
    }
  }
}
