// lib/features/tenant/debug_membership_banner.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // kReleaseMode
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tenant_provider.dart';
import 'membership_guard.dart';

class DebugMembershipBanner extends ConsumerWidget {
  const DebugMembershipBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🔒 Nunca aparece em release (APK)
    if (kReleaseMode) return const SizedBox.shrink();

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

      ref.invalidate(membershipProvider(tenantId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesso reparado (admin/active=true).')),
      );
    }

    Future<void> testarLeitura() async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .limit(1)
            .get();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Leitura OK (${snap.size} doc(s))')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha leitura: $e')),
        );
      }
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tenant: $tenantId · UID: $uid · $status',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              TextButton.icon(
                onPressed: testarLeitura,
                icon: const Icon(Icons.visibility),
                label: const Text('Testar leitura'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: reparar,
                icon: const Icon(Icons.build),
                label: const Text('Reparar acesso'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
