import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/product.dart';
import '../tenant/tenant_provider.dart';
import '../../data/datasources/stock_service.dart';

final _catalogProvider = StreamProvider.autoDispose<List<(Product, int)>>((
  ref,
) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();

  final col = FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('produtos')
      .orderBy('nome');

  // carregamos products e inicializamos qty 0
  return col.snapshots().map((s) {
    return s.docs.map((d) {
      final p = Product.fromMap(d.id, d.data());
      return (p, 0); // tuple: (product, qty)
    }).toList();
  });
});

class ManualSaleCatalogPage extends ConsumerStatefulWidget {
  const ManualSaleCatalogPage({super.key});
  @override
  ConsumerState<ManualSaleCatalogPage> createState() =>
      _ManualSaleCatalogPageState();
}

class _ManualSaleCatalogPageState extends ConsumerState<ManualSaleCatalogPage> {
  String _q = '';
  final _qty = <String, int>{}; // productId -> qty

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_catalogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vender (catálogo)')),
      body: async.when(
        data: (items) {
          final filtered = items.where((e) {
            final p = e.$1;
            if (_q.isEmpty) return true;
            return p.nome.toLowerCase().contains(_q) ||
                p.categoria.toLowerCase().contains(_q) ||
                (p.sku ?? '').toLowerCase().contains(_q);
          }).toList();

          return Column(
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
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = filtered[i].$1;
                    final q = _qty[p.id] ?? 0;
                    final se = p.quantidade <= 0;
                    final low = !se && p.quantidade <= p.estoqueMinimo;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            p.nome.isNotEmpty ? p.nome[0].toUpperCase() : '?',
                          ),
                        ),
                        title: Text(p.nome),
                        subtitle: Text(
                          [
                            if (p.categoria.isNotEmpty) p.categoria,
                            if ((p.sku ?? '').isNotEmpty) 'SKU: ${p.sku}',
                            'Estoque: ${p.quantidade}',
                            if (p.preco > 0)
                              'R\$ ${p.preco.toStringAsFixed(2)}',
                          ].join('  •  '),
                        ),
                        trailing: SizedBox(
                          width: 140,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: q > 0
                                    ? () => setState(() => _qty[p.id] = q - 1)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text(
                                '$q',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(
                                  () => _qty[p.id] = (q + 1).clamp(0, 99999),
                                ),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Finalizar venda'),
                      onPressed: _finalizarVenda,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
      ),
    );
  }

  Future<void> _finalizarVenda() async {
    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione/entre em uma loja.')),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    final service = StockService(db, tenantId);

    // monta linhas (apenas qty > 0)
    final lines = <SaleLine>[];
    double total = 0.0;

    // Para pegar preços, vamos buscar snapshot atual dos produtos usados:
    final selectedIds = _qty.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList();
    if (selectedIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nenhum item selecionado.')));
      return;
    }

    final prodsSnap = await db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .where(
          FieldPath.documentId,
          whereIn: selectedIds.length > 10
              ? selectedIds.sublist(0, 10)
              : selectedIds,
        )
        .get();

    // Nota: Firestore whereIn suporta até 10 itens por consulta; para carrinhos grandes, faça em lotes.
    final byId = {for (final d in prodsSnap.docs) d.id: d.data()};

    for (final entry in _qty.entries) {
      final q = entry.value;
      if (q <= 0) continue;
      final data = byId[entry.key];
      if (data == null) continue;
      final precoAny = data['valor'] ?? data['preco'] ?? 0;
      final preco = precoAny is num
          ? precoAny.toDouble()
          : double.tryParse('$precoAny') ?? 0.0;
      total += preco * q;
      lines.add(SaleLine(produtoId: entry.key, qty: q, unitPrice: preco));
    }

    if (lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nada a vender.')));
      return;
    }

    try {
      await service.createSaleAndApply(
        lines: lines,
        usuarioId: uid,
        total: total,
        origem: 'manual_sale',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Venda registrada.')));
      setState(() => _qty.clear());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }
}
