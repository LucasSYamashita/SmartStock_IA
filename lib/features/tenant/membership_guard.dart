import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'tenant_provider.dart';
import 'tenant_join_create_page.dart';

/// Stream do membership do usuário logado para um tenant específico.
final membershipProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, tenantId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid)
      .snapshots()
      .map((d) => d.data());
});

/// Gate que exige o usuário ser membro do tenant atual.
/// Se não houver tenant selecionado ou membership, manda para Join/Create.
class RequireMember extends ConsumerWidget {
  final Widget child;
  final Widget? loading;
  final Widget? notMember;

  const RequireMember({
    super.key,
    required this.child,
    this.loading,
    this.notMember,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const TenantJoinCreatePage();
    }

    final async = ref.watch(membershipProvider(tenantId));
    return async.when(
      loading: () =>
          loading ??
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Erro membership: $e'))),
      data: (m) {
        if (m == null || (m['active'] == false)) {
          return notMember ?? const TenantJoinCreatePage();
        }
        return child;
      },
    );
  }
}
