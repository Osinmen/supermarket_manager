import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/permissions.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_controller.dart';
import 'package:supermarket/features/auth/presentation/users_screen.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, [this.permission]);

  final String label;
  final IconData icon;
  final Permission? permission;
}

const _allItems = [
  _NavItem('Dashboard', Icons.space_dashboard_outlined),
  _NavItem('Point of Sale', Icons.point_of_sale, Permission.makeSale),
  _NavItem('Products', Icons.sell_outlined, Permission.manageProducts),
  _NavItem('Inventory', Icons.inventory_2_outlined, Permission.viewProducts),
  _NavItem('Reports', Icons.bar_chart_outlined, Permission.viewReports),
  _NavItem('Users', Icons.group_outlined, Permission.manageUsers),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    final items = _allItems
        .where((i) => i.permission == null || user.can(i.permission!))
        .toList();
    final current = items[_selected.clamp(0, items.length - 1)];

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            items: items,
            selected: items.indexOf(current),
            user: user,
            onSelect: (i) => setState(() => _selected = i),
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: current.label, user: user),
                                Expanded(
                  child: current.label == 'Users'
                      ? const UsersScreen()
                      : _PlaceholderPage(title: current.label),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.user,
    required this.onSelect,
    required this.onLogout,
  });

  final List<_NavItem> items;
  final int selected;
  final AppUser user;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.navy,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.sidebarLine)),
            ),
            child: const Row(
              children: [
                Icon(Icons.storefront_outlined, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'SUPERMARKET',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < items.length; i++)
                  _SidebarTile(
                    item: items[i],
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.sidebarLine)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.role.name.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.sidebarMuted,
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: onLogout,
                  icon: const Icon(
                    Icons.logout,
                    size: 18,
                    color: AppColors.sidebarText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.sidebarText;

    return Material(
      color: selected ? AppColors.sidebarHover : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.sidebarHover,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? AppColors.accent : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.user});

  final String title;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            user.username,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title: coming soon',
        style: const TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}