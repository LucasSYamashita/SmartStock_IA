import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';

/// Admin = role 'admin' no membership da loja atual
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

/// Stream de produtos
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

enum StockFilter { all, se, low, ok }

class ProductListPage extends ConsumerStatefulWidget {
  const ProductListPage({super.key});

  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
  String _query = '';
  StockFilter _filter = StockFilter.all;

  @override
  Widget build(BuildContext context) {
    final productsSnap = ref.watch(_productsProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Busca
          TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar por nome ou marca…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 10),

          // Filtros de estoque
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Todos'),
                selected: _filter == StockFilter.all,
                onSelected: (_) => setState(() => _filter = StockFilter.all),
              ),
              FilterChip(
                label: const Text('S/E'),
                selected: _filter == StockFilter.se,
                onSelected: (_) => setState(() => _filter = StockFilter.se),
              ),
              FilterChip(
                label: const Text('Baixo'),
                selected: _filter == StockFilter.low,
                onSelected: (_) => setState(() => _filter = StockFilter.low),
              ),
              FilterChip(
                label: const Text('OK'),
                selected: _filter == StockFilter.ok,
                onSelected: (_) => setState(() => _filter = StockFilter.ok),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Lista
          Expanded(
            child: productsSnap.when(
              data: (snap) {
                if (snap.docs.isEmpty) {
                  return const Center(
                    child: Text('Sem produtos nesta loja. Use o + para criar.'),
                  );
                }

                // filtra e mapeia
                final items = snap.docs.where((doc) {
                  final m = doc.data();
                  final nome = (m['nome'] ?? m['Nome'] ?? '').toString();
                  final marca = (m['marca'] ?? m['Marca'] ?? '').toString();
                  if (_query.isNotEmpty) {
                    final n = nome.toLowerCase();
                    final mm = marca.toLowerCase();
                    if (!(n.contains(_query) || mm.contains(_query))) {
                      return false;
                    }
                  }

                  final qtdAny = m['quantidade'] ?? m['Quantidade'] ?? 0;
                  final minAny = m['estoqueMinimo'] ?? m['EstoqueMinimo'] ?? 0;
                  final qtd = qtdAny is num
                      ? qtdAny.toInt()
                      : int.tryParse('$qtdAny') ?? 0;
                  final min = minAny is num
                      ? minAny.toInt()
                      : int.tryParse('$minAny') ?? 0;

                  switch (_filter) {
                    case StockFilter.all:
                      return true;
                    case StockFilter.se:
                      return qtd <= 0;
                    case StockFilter.low:
                      return qtd > 0 && qtd <= min;
                    case StockFilter.ok:
                      return qtd > min;
                  }
                }).toList();

                if (items.isEmpty) {
                  return const Center(
                      child: Text('Nenhum item com esse filtro/busca.'));
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final d = items[i].data();

                    final nome = (d['nome'] ?? d['Nome'] ?? '').toString();
                    final marca = (d['marca'] ?? d['Marca'] ?? '').toString();

                    final qtdAny = d['quantidade'] ?? d['Quantidade'] ?? 0;
                    final minAny =
                        d['estoqueMinimo'] ?? d['EstoqueMinimo'] ?? 0;
                    final valorAny = d['valor'] ?? d['precoVenda'] ?? 0;

                    final qtd = qtdAny is num
                        ? qtdAny.toInt()
                        : int.tryParse('$qtdAny') ?? 0;
                    final min = minAny is num
                        ? minAny.toInt()
                        : int.tryParse('$minAny') ?? 0;
                    final valor = valorAny is num
                        ? valorAny.toDouble()
                        : double.tryParse('$valorAny') ?? 0.0;

                    // status: S/E -> Baixo -> OK
                    Widget trailing;
                    if (qtd <= 0) {
                      trailing = Chip(
                        label: const Text('S/E'),
                        avatar: const Icon(Icons.block, size: 16),
                        backgroundColor:
                            Theme.of(context).colorScheme.errorContainer,
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

                    final parts = <String>[
                      'Qtd: $qtd',
                      'Min: $min',
                      if (marca.isNotEmpty) marca,
                      if (valor > 0) _fmt(valor),
                    ];

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                              nome.isNotEmpty ? nome[0].toUpperCase() : '?'),
                        ),
                        title: Text(nome),
                        subtitle: Text(parts.join('  •  ')),
                        trailing: trailing,
                        onTap: () {
                          // TODO: detalhes/editar produto
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
