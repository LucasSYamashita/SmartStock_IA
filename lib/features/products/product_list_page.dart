import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';

final isAdminProvider = StreamProvider<bool>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (tenantId == null || uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid)
      .snapshots()
      .map((d) => (d.data()?['role'] ?? '') == 'admin');
});

final _productsProvider =
    StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('produtos')
      .orderBy('nome')
      .snapshots();
});

String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

class ProductListPage extends ConsumerWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsSnap = ref.watch(_productsProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: productsSnap.when(
        data: (snap) {
          if (snap.docs.isEmpty) {
            return const Center(
              child: Text('Sem produtos nesta loja. Use o + para criar.'),
            );
          }
          return ListView.separated(
            itemCount: snap.docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final d = snap.docs[i].data();

              final nome = (d['nome'] ?? d['Nome'] ?? '').toString();

              // campos unificados c/ fallback
              final qtdAny = d['quantidade'] ?? d['Quantidade'] ?? 0;
              final minAny = d['estoqueMinimo'] ?? d['EstoqueMinimo'] ?? 0;
              final valorAny = d['valor'] ?? d['precoVenda'] ?? 0;
              final marca = (d['marca'] ?? d['Marca'] ?? '').toString();

              final qtd =
                  qtdAny is num ? qtdAny.toInt() : int.tryParse('$qtdAny') ?? 0;
              final min =
                  minAny is num ? minAny.toInt() : int.tryParse('$minAny') ?? 0;
              final valor = valorAny is num
                  ? valorAny.toDouble()
                  : double.tryParse('$valorAny') ?? 0.0;

              // status: S/E primeiro; depois Baixo
              Widget trailing;
              if (qtd <= 0) {
                trailing = Chip(
                  label: const Text('S/E'),
                  avatar: const Icon(Icons.block, size: 16),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                );
              } else if (qtd <= min) {
                trailing = const Chip(
                  label: Text('Baixo'),
                  avatar: Icon(Icons.warning_amber, size: 16),
                );
              } else {
                trailing = const Icon(Icons.chevron_right);
              }

              final extra = <String>[];
              extra.add('Qtd: $qtd');
              extra.add('Min: $min');
              if (marca.isNotEmpty) extra.add(marca);
              if (valor > 0) extra.add(_fmt(valor));

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?'),
                  ),
                  title: Text(nome),
                  subtitle: Text(extra.join('  •  ')),
                  trailing: trailing,
                  onTap: () {}, // futuro: detalhes/editar
                ),
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
