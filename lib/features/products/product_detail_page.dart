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
      return const Scaffold(
        body: Center(child: Text('Selecione uma loja.')),
      );
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
            tooltip: 'Registrar entrada / ajustar preço',
            icon: const Icon(Icons.call_received),
            onPressed: () => _showEntradaDialog(context, tenantId),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data();
          if (data == null) {
            return const Center(child: Text('Produto não encontrado.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _row('Nome', (data['nome'] ?? '').toString()),
              _row('Categoria', (data['categoria'] ?? '').toString()),
              _row('SKU', (data['sku'] ?? '').toString()),
              _row(
                'Preço',
                'R\$ ${((data['preco'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
              ),
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
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                k,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  double _parseDouble(String raw) {
    final s = raw
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }

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
            final custoRaw = custoCtrl.text.trim();
            final hasCusto = custoRaw.isNotEmpty;
            final custo = hasCusto ? _parseDouble(custoRaw) : null;

            if (qtd < 0) {
              setLocal(() => err = 'Quantidade não pode ser negativa.');
              return;
            }
            if (custo != null && custo < 0) {
              setLocal(() => err = 'Custo não pode ser negativo.');
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

              // ============================
              // CASO 1 — Apenas ajustar preço (qtd == 0)
              // ============================
              if (qtd == 0) {
                if (!hasCusto) {
                  setLocal(() => err =
                      'Informe o preço para atualizar ou uma quantidade > 0.');
                  return;
                }

                await prodRef.update({
                  'preco': custo,
                  'updatedAt': FieldValue.serverTimestamp(),
                  'updatedBy': uid,
                });

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Preço do produto atualizado.'),
                  ),
                );
                return;
              }

              // ============================
              // CASO 2 — Entrada normal (qtd > 0)
              // ============================

              final txResult =
                  await db.runTransaction<Map<String, dynamic>>((tx) async {
                final snap = await tx.get(prodRef);
                if (!snap.exists) {
                  throw Exception('Produto não encontrado.');
                }

                final data = snap.data() ?? {};
                final nome = (data['nome'] ?? '').toString();
                final atualQtd = (data['quantidade'] as int?) ?? 0;
                final precoAtual = (data['preco'] as num?)?.toDouble() ?? 0.0;

                // se informou custo, passa a ser o novo preço padrão
                final precoFinal =
                    (custo != null && custo >= 0) ? custo : precoAtual;

                final novoEstoque = atualQtd + qtd;

                final updateData = <String, dynamic>{
                  'quantidade': novoEstoque,
                  'updatedAt': FieldValue.serverTimestamp(),
                  'updatedBy': uid,
                };
                if (hasCusto) {
                  updateData['preco'] = precoFinal;
                }

                tx.update(prodRef, updateData);

                return {
                  'nome': nome,
                  'preco': precoFinal,
                  'novoEstoque': novoEstoque,
                };
              });

              final nomeProd = (txResult['nome'] ?? '') as String? ?? '';
              final precoMov = (txResult['preco'] as num?)?.toDouble() ?? 0.0;
              final total = precoMov * qtd;

              await db
                  .collection('tenants')
                  .doc(tenantId)
                  .collection('movimentos')
                  .add({
                'tipo': 'entrada',
                'quantidade': qtd,
                'produtoId': widget.productId,
                'produtoNome': nomeProd,
                'preco': precoMov,
                'valorTotal': total,
                'usuarioId': uid,
                'tenantId': tenantId,
                'origem': 'product_detail',
                'motivo': 'entrada manual',
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Entrada de +qtdx $nomeProd registrada. '
                    'Preço R\$ ${precoMov.toStringAsFixed(2)}.',
                  ),
                ),
              );
            } catch (e) {
              setLocal(() => err = 'Falha: $e');
            }
          }

          return AlertDialog(
            title: const Text('Registrar entrada / ajustar preço'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: qtdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade (+)',
                      helperText:
                          'Use 0 para não alterar o estoque (apenas preço).',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: custoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Custo / preço unitário (opcional)',
                      hintText: 'Ex.: 12,34',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        err!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: salvar,
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
