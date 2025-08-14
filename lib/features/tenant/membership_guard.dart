import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/tenant/tenant_provider.dart';
import '../../features/tenant/tenant_join_create_page.dart';

class MembershipGuard extends ConsumerWidget {
  final Widget child;
  const MembershipGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (tenantId == null || uid == null) {
      return const TenantJoinCreatePage();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || !snap.data!.exists) {
          // não é membro → ir para a tela de entrar/criar loja
          return const TenantJoinCreatePage();
        }
        return child;
      },
    );
  }
}
