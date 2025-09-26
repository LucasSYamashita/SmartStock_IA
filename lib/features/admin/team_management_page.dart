import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';

class TeamManagementPage extends ConsumerWidget {
  const TeamManagementPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(body: Center(child: Text('Selecione uma loja.')));
    }

    final q = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('usuarios')
        .where('role', whereIn: ['staff', 'admin']).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Equipe')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs.toList()
            ..sort((a, b) => (a.data()['role'] as String)
                .compareTo(b.data()['role'] as String));
          if (docs.isEmpty) return const Center(child: Text('Sem membros.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();
              final isAdmin = (m['role'] ?? '') == 'admin';
              final active = (m['active'] ?? true) as bool;
              final name = (m['displayName'] ?? m['email'] ?? d.id).toString();

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                      child:
                          Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                  title: Text(name),
                  subtitle: Text(
                      '${m['email'] ?? ''} • ${isAdmin ? 'ADMIN' : 'STAFF'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: active,
                        onChanged: (v) => d.reference.update({
                          'active': v,
                          'updatedAt': FieldValue.serverTimestamp()
                        }),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'promote') {
                            d.reference.update({
                              'role': 'admin',
                              'updatedAt': FieldValue.serverTimestamp()
                            });
                          }
                          if (v == 'demote') {
                            d.reference.update({
                              'role': 'staff',
                              'updatedAt': FieldValue.serverTimestamp()
                            });
                          }
                          if (v == 'remove') d.reference.delete();
                        },
                        itemBuilder: (_) => [
                          if (!isAdmin)
                            const PopupMenuItem(
                                value: 'promote',
                                child: Text('Promover a admin')),
                          if (isAdmin)
                            const PopupMenuItem(
                                value: 'demote',
                                child: Text('Rebaixar para staff')),
                          const PopupMenuItem(
                              value: 'remove', child: Text('Remover da loja')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
