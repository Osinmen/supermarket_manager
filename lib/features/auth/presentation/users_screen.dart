import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../database/enums.dart';
import '../data/user_repository.dart';
import '../domain/app_user.dart';
import 'auth_controller.dart';
import 'auth_layout.dart';

String _roleLabel(UserRole role) =>
    role.name[0].toUpperCase() + role.name.substring(1);

final _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

/// Runs an action and reports the result (or the error) in a snackbar.
Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
  String doneMessage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
  } on AppException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Something went wrong. Try again.')),
    );
  }
}

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider);
    final users = ref.watch(usersProvider);
    if (me == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Staff accounts',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Add user'),
                onPressed: () async {
                  final created = await showDialog<bool>(
                    context: context,
                    builder: (_) => _AddUserDialog(actor: me),
                  );
                  if (created == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User created.')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: users.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text("Couldn't load users.")),
                data: (list) => Column(
                  children: [
                    const _HeaderRow(),
                    const Divider(),
                    Expanded(
                      child: ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, i) =>
                            _UserRow(user: list[i], me: me),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );

    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('NAME', style: style)),
          Expanded(flex: 2, child: Text('ROLE', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          Expanded(flex: 3, child: Text('LAST LOGIN', style: style)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user, required this.me});

  final AppUser user;
  final AppUser me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = user.id == me.id;
    final repo = ref.read(userRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${user.fullName} (you)' : user.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  user.username,
                  style: AppTheme.numeric.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Chip(
                label: _roleLabel(user.role),
                textColor: AppColors.navy,
                background: AppColors.canvas,
                bordered: true,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: user.isActive
                  ? const _Chip(
                      label: 'Active',
                      textColor: AppColors.navy,
                      background: AppColors.canvas,
                      bordered: true,
                    )
                  : const _Chip(
                      label: 'Disabled',
                      textColor: AppColors.danger,
                      background: AppColors.dangerSoft,
                    ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user.lastLoginAt == null
                  ? 'Never'
                  : _dateFormat.format(user.lastLoginAt!),
              style: AppTheme.numeric.copyWith(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (value) async {
                switch (value) {
                  case 'role':
                    final role = await showDialog<UserRole>(
                      context: context,
                      builder: (_) => _RoleDialog(current: user.role),
                    );
                    if (role != null && context.mounted) {
                      await _guard(
                        context,
                        () => repo.changeRole(
                          actor: me,
                          userId: user.id,
                          role: role,
                        ),
                        'Role updated.',
                      );
                    }
                  case 'password':
                    final password = await showDialog<String>(
                      context: context,
                      builder: (_) => _PasswordDialog(name: user.fullName),
                    );
                    if (password != null && context.mounted) {
                      await _guard(
                        context,
                        () => repo.resetPassword(
                          actor: me,
                          userId: user.id,
                          newPassword: password,
                        ),
                        'Password reset.',
                      );
                    }
                  case 'toggle':
                    await _guard(
                      context,
                      () => repo.setActive(
                        actor: me,
                        userId: user.id,
                        isActive: !user.isActive,
                      ),
                      user.isActive ? 'Account disabled.' : 'Account enabled.',
                    );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'role',
                  enabled: !isMe,
                  child: const Text('Change role'),
                ),
                const PopupMenuItem(
                  value: 'password',
                  child: Text('Reset password'),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  enabled: !isMe,
                  child: Text(user.isActive ? 'Disable account' : 'Enable account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.textColor,
    required this.background,
    this.bordered = false,
  });

  final String label;
  final Color textColor;
  final Color background;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.radius,
        border: bordered ? Border.all(color: AppColors.border) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ dialogs

class _AddUserDialog extends ConsumerStatefulWidget {
  const _AddUserDialog({required this.actor});

  final AppUser actor;

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9._]{3,40}$');

  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  UserRole _role = UserRole.cashier;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(userRepositoryProvider).createUser(
            actor: widget.actor,
            fullName: _fullName.text,
            username: _username.text,
            password: _password.text,
            role: _role,
          );
      if (mounted) Navigator.of(context).pop(true);
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
    return AlertDialog(
      title: const Text('Add user'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  AuthErrorBox(_error!),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _fullName,
                  autofocus: true,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText: 'Letters, numbers, dot or underscore',
                  ),
                  validator: (v) => _usernamePattern.hasMatch(v?.trim() ?? '')
                      ? null
                      : '3 to 40 characters: letters, numbers, . or _',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'Shown as you type so you can tell the staff',
                  ),
                  validator: (v) => PasswordHasher.validate(v ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(
                      value: UserRole.cashier,
                      child: Text('Cashier'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.manager,
                      child: Text('Manager'),
                    ),
                  ],
                  onChanged:
                      _busy ? null : (r) => setState(() => _role = r ?? _role),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create user'),
        ),
      ],
    );
  }
}

class _RoleDialog extends StatefulWidget {
  const _RoleDialog({required this.current});

  final UserRole current;

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late UserRole _role = widget.current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change role'),
      content: SizedBox(
        width: 320,
        child: DropdownButtonFormField<UserRole>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items: [
            for (final r in UserRole.values)
              DropdownMenuItem(value: r, child: Text(_roleLabel(r))),
          ],
          onChanged: (r) => setState(() => _role = r ?? _role),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_role),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.name});

  final String name;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset password for ${widget.name}'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _password,
            autofocus: true,
            autocorrect: false,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'New temporary password',
              helperText: 'Shown as you type so you can tell the staff',
            ),
            validator: (v) => PasswordHasher.validate(v ?? ''),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Reset password')),
      ],
    );
  }
}