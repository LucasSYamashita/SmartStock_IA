import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tenant_provider.dart';
import 'membership_guard.dart';

class DebugMembershipBanner extends ConsumerWidget {
  const DebugMembershipBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (tenantId == null || uid == null) return const SizedBox.shrink();

    final m = ref.watch(membershipProvider(tenantId));
    final status = m.when<String>(
      loading: () => 'Carregando...',
      error: (e, _) => 'Erro: $e',
      data: (d) {
        if (d == null) return 'Sem membership';
        final role = d['role'];
        final active = d['active'];
        return 'role=${role ?? "(null)"} · active=${active ?? "(null)"}';
      },
    );

    Future<void> reparar() async {
      final db = FirebaseFirestore.instance;
      final doc = db
          .collection('tenants')
          .doc(tenantId)
          .collection('usuarios')
          .doc(uid);

      await doc.set({
        'role': 'admin',
        'active': true,
        'displayName': FirebaseAuth.instance.currentUser?.displayName ?? '',
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // força refresh
      ref.invalidate(membershipProvider(tenantId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesso reparado (staff/active=true).')),
      );
    }

    return Material(
      color: Colors.amber.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tenant: $tenantId · UID: $uid · $status',
                style: Theme.of(context).textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.build, size: 16),
              label: const Text('Reparar acesso'),
              onPressed: reparar,
            ),
          ],
        ),
      ),
    );
  }
}
