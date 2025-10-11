// lib/features/auth/role_guard.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartstock_flutter_only/features/tenant/tenant_gate.dart';

import '../tenant/tenant_provider.dart';
import '../tenant/tenant_join_create_page.dart';
import '../tenant/membership_guard.dart' show membershipProvider;

import 'auth_providers.dart' show Role;

/// Exige um papel mínimo (viewer < staff < admin)
class RequireRole extends ConsumerWidget {
  final Role minRole;
  final Widget child;

  /// (opcionais) personalize telas de estados
  final Widget? loading;
  final Widget? notLoggedOrNoTenant; // sem tenant selecionado
  final Widget? notMember; // não é membro do tenant
  final Widget? notEnough; // não tem permissão

  const RequireRole({
    super.key,
    required this.minRole,
    required this.child,
    this.loading,
    this.notLoggedOrNoTenant,
    this.notMember,
    this.notEnough,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return notLoggedOrNoTenant ?? const TenantJoinCreatePage();
    }

    final async = ref.watch(membershipProvider(tenantId));
    return async.when(
      loading: () =>
          loading ??
          const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro: $e'))),
      data: (m) {
        // m pode ser null (não é membro) ou não ter 'active'
        final isActive = (m?['active'] as bool?) ?? true;
        if (m == null || !isActive) {
          return notMember ?? const TenantJoinCreatePage();
        }

        final roleStr = (m['role'] ?? 'viewer').toString().trim().toLowerCase();
        final ok = _rank(roleStr) >= _rankFromEnum(minRole);

        if (ok) return child;

        return notEnough ??
            const Scaffold(
              body: Center(child: Text('Permissão insuficiente.')),
            );
      },
    );
  }

  int _rank(String r) {
    switch (r) {
      case 'admin':
        return 3;
      case 'staff':
        return 2;
      default:
        return 1; // viewer (ou qualquer outro vira viewer)
    }
  }

  int _rankFromEnum(Role r) {
    switch (r) {
      case Role.admin:
        return 3;
      case Role.staff:
        return 2;
      case Role.viewer:
      default:
        return 1;
    }
  }
}
