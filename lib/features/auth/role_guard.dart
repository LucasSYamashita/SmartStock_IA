import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';

class RequireRole extends ConsumerWidget {
  final Role minRole;
  final Widget child;
  const RequireRole({super.key, required this.minRole, required this.child});

  bool _hasAccess(Role current) {
    int rank(Role r) => r == Role.admin ? 3 : (r == Role.staff ? 2 : 1);
    return rank(current) >= rank(minRole);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    if (_hasAccess(role)) return child;
    return const Center(child: Text('Permissão insuficiente.'));
  }
}
