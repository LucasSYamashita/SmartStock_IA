import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tenant/tenant_provider.dart';
import '../../features/tenant/tenant_join_create_page.dart';

/// Observa o documento de membership do usuário na loja.
/// Retorna o Map com os campos do membership ou null se não existir.
final membershipProvider =
    StreamProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, tenantId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    final docRef = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('usuarios')
        .doc(uid);

    // Evita rebuilds quando nada mudou.
    return docRef.snapshots().map((s) => s.data()).distinct(mapEquals);
  },
);

/// Guarda que exige o usuário pertencer ao tenant selecionado.
/// Se [adminOnly] = true, só permite acesso para role == 'admin'.
class MembershipGuard extends ConsumerWidget {
  final Widget child;

  /// Exigir permissão de admin?
  final bool adminOnly;

  /// Widgets opcionais
  final Widget? loading;
  final Widget? notMember;
  final Widget? notAdmin;
  final Widget? notLogged;

  const MembershipGuard({
    super.key,
    required this.child,
    this.adminOnly = false,
    this.loading,
    this.notMember,
    this.notAdmin,
    this.notLogged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return notLogged ??
          const Scaffold(
            body: Center(child: Text('Faça login para continuar.')),
          );
    }

    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      // Logado, mas ainda não escolheu/entrou numa loja
      return const TenantJoinCreatePage();
    }

    final asyncMembership = ref.watch(membershipProvider(tenantId));

    return asyncMembership.when(
      loading: () =>
          loading ??
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          body: Center(child: Text('Erro ao carregar permissões: $e'))),
      data: (m) {
        if (m == null) {
          // Não é membro da loja atual
          return notMember ?? const TenantJoinCreatePage();
        }

        final role = (m['role'] ?? '').toString();
        if (adminOnly && role != 'admin') {
          return notAdmin ??
              Scaffold(
                appBar: AppBar(title: const Text('Permissão insuficiente')),
                body: const Center(
                  child:
                      Text('Você não tem acesso de administrador nesta loja.'),
                ),
              );
        }

        return child;
      },
    );
  }
}

/// Atalho de uso comum: exige ser membro da loja atual.
class RequireMember extends ConsumerWidget {
  final Widget child;
  const RequireMember({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MembershipGuard(child: child);
  }
}

/// Atalho de uso comum: exige ser ADMIN da loja atual.
class RequireAdmin extends ConsumerWidget {
  final Widget child;
  const RequireAdmin({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MembershipGuard(adminOnly: true, child: child);
  }
}
