import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tenant_provider.dart';

/// Lista todas as lojas nas quais o usuário é membro, via collectionGroup("usuarios")
final myTenantsProvider =
    StreamProvider<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  final cg = FirebaseFirestore.instance
      .collectionGroup('usuarios')
      .where('uid', isEqualTo: uid);
  return cg.snapshots().map((snap) => snap.docs);
});

class TenantPickerPage extends ConsumerWidget {
  const TenantPickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myTenantsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas lojas')),
      body: async.when(
        data: (docs) {
          if (docs.isEmpty) {
            return const Center(
                child: Text('Você ainda não participa de nenhuma loja.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final userDoc = docs[i]; // .../tenants/{id}/usuarios/{uid}
              final usuarioPath = userDoc.reference.path;
              final tenantId = userDoc.reference.parent.parent!.id;

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('tenants')
                    .doc(tenantId)
                    .get(),
                builder: (context, snap) {
                  final name =
                      snap.data?.data()?['name']?.toString() ?? '(sem nome)';
                  final role = (userDoc.data()['role'] ?? 'viewer').toString();
                  final active = (userDoc.data()['active'] ?? true) == true;

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.store_mall_directory_outlined),
                      title: Text(name),
                      subtitle: Text(
                          'Papel: $role • ${active ? "Ativo" : "Inativo"}'),
                      trailing: active
                          ? const Icon(Icons.chevron_right)
                          : const Icon(Icons.block, color: Colors.redAccent),
                      onTap: active
                          ? () async {
                              await ref
                                  .read(tenantIdProvider.notifier)
                                  .set(tenantId);
                              if (context.mounted) Navigator.of(context).pop();
                            }
                          : null,
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
      ),
    );
  }
}
