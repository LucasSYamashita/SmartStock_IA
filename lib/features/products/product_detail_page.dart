import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';

class ProductDetailPage extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailPage({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(body: Center(child: Text('Selecione uma loja.')));
    }

    final docRef = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(widget.productId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produto'),
        actions: [
          IconButton(
            tooltip: 'Registrar entrada',
            icon: const Icon(Icons.call_received),
            onPressed: () => _showEntradaDialog(context, tenantId),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snap.data!.data();
          if (data == null)
            return const Center(child: Text('Produto não encontrado.'));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _row('Nome', (data['nome'] ?? '').toString()),
              _row('Categoria', (data['categoria'] ?? '').toString()),
              _row('SKU', (data['sku'] ?? '').toString()),
              _row('Preço',
                  'R\$ ${((data['preco'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
              _row('Quantidade', '${data['quantidade'] ?? 0}'),
              _row('Estoque mínimo', '${data['estoqueMinimo'] ?? 0}'),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 150,
              child:
                  Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );

  Future<void> _showEntradaDialog(BuildContext context, String tenantId) async {
    final qtdCtrl = TextEditingController(text: '1');
    final custoCtrl = TextEditingController();
    String? err;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> salvar() async {
            final qtd = int.tryParse(qtdCtrl.text.trim()) ?? 0;
            final custo = double.tryParse(custoCtrl.text.trim());

            if (qtd <= 0) {
              setLocal(() => err = 'Informe uma quantidade válida (>0).');
              return;
            }

            final db = FirebaseFirestore.instance;
            final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

            try {
              final prodRef = db
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('produtos')
                  .doc(widget.productId);

              await db.runTransaction((tx) async {
                final snap = await tx.get(prodRef);
                if (!snap.exists) throw Exception('Produto não encontrado.');
                final atual = (snap.data()?['quantidade'] ?? 0) as int;
                tx.update(prodRef, {
                  'quantidade': atual + qtd,
                  'updatedAt': FieldValue.serverTimestamp(),
                  'updatedBy': uid,
                });
              });

              final total = (custo ?? 0) * qtd;

              await db
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('movimentos')
                  .add({
                'tipo': 'entrada',
                'quantidade': qtd,
                'produtoId': widget.productId,
                'usuarioId': uid,
                'origem': 'product_detail',
                'motivo': 'entrada manual',
                if (custo != null) 'unitCost': custo,
                'totalValue': total,
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Entrada registrada.')),
              );
            } catch (e) {
              setLocal(() => err = 'Falha: $e');
            }
          }

          return AlertDialog(
            title: const Text('Registrar entrada'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: qtdCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Quantidade (+)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: custoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Custo unitário (opcional)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child:
                          Text(err!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              FilledButton(onPressed: salvar, child: const Text('Salvar')),
            ],
          );
        },
      ),
    );
  }
}
