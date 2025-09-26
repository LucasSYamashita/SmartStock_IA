import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firestore_products.dart';
import '../../data/models/product.dart';
import '../tenant/tenant_provider.dart';
import '../auth/auth_providers.dart'; // isAdminProvider
import 'product_editor_page.dart'; // >>> importe o editor

String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

final _productsProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();
  final db = FirebaseFirestore.instance;
  return FirestoreProducts(db, tenantId).streamAll();
});

class ProductListPage extends ConsumerStatefulWidget {
  const ProductListPage({super.key});
  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_productsProvider);
    final isAdmin = ref.watch(
        isAdminProvider); // se quiser permitir staff: use isStaffProvider

    return Scaffold(
      appBar: AppBar(title: const Text('Produtos')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProductEditorPage()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nome, categoria ou SKU…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: async.when(
              data: (items) {
                final list = items.where((p) {
                  if (_q.isEmpty) return true;
                  final n = p.nome.toLowerCase();
                  final c = p.categoria.toLowerCase();
                  final s = (p.sku ?? '').toLowerCase();
                  return n.contains(_q) || c.contains(_q) || s.contains(_q);
                }).toList();

                if (list.isEmpty) {
                  return const Center(
                      child: Text('Nenhum produto encontrado.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final se = p.quantidade <= 0;
                    final low = !se && p.quantidade <= p.estoqueMinimo;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(p.nome.isNotEmpty
                              ? p.nome[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(p.nome),
                        subtitle: Text([
                          if (p.categoria.isNotEmpty) p.categoria,
                          if ((p.sku ?? '').isNotEmpty) 'SKU: ${p.sku}',
                          'Qtd: ${p.quantidade}',
                          'Min: ${p.estoqueMinimo}',
                          if (p.preco > 0) _fmt(p.preco),
                        ].join('  •  ')),
                        trailing: se
                            ? const Chip(
                                label: Text('S/E'),
                                avatar: Icon(Icons.block, size: 16))
                            : (low
                                ? const Chip(
                                    label: Text('Baixo'),
                                    avatar: Icon(Icons.warning_amber, size: 16))
                                : const Icon(Icons.chevron_right)),
                        // >>> TOQUE PARA EDITAR (só admin; troque para staff/admin se quiser)
                        onTap: isAdmin
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ProductEditorPage(productId: p.id),
                                  ),
                                );
                              }
                            : null,
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
