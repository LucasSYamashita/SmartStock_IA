import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});

  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _idCtrl = TextEditingController(); // pode ficar vazio (gera id)
  final _qtdCtrl = TextEditingController(text: '1');
  final _custoCtrl = TextEditingController(text: '0');
  final _motivoCtrl = TextEditingController(text: 'compra');

  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _idCtrl.dispose();
    _qtdCtrl.dispose();
    _custoCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  double _parseDouble(String raw) {
    final s = raw
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }

  Future<void> _save() async {
    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null || tenantId.isEmpty) {
      setState(() => _err = 'Selecione/abra uma loja.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _err = 'Faça login para registrar entrada.');
      return;
    }

    final qtd = int.tryParse(_qtdCtrl.text.trim()) ?? 0;
    final custo = _parseDouble(_custoCtrl.text);
    var prodId = _idCtrl.text.trim();
    final motivo = _motivoCtrl.text.trim();

    if (qtd <= 0) {
      setState(() => _err = 'Quantidade deve ser maior que zero.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final prods =
          db.collection('tenants').doc(tenantId).collection('produtos');
      final movs =
          db.collection('tenants').doc(tenantId).collection('movimentos');

      // 1) Garante um ID de produto
      DocumentReference<Map<String, dynamic>> prodRef;
      DocumentSnapshot<Map<String, dynamic>> prodSnap;

      if (prodId.isEmpty) {
        // se não veio id, gera um doc novo
        prodRef = prods.doc();
        prodId = prodRef.id;
        prodSnap = await prodRef.get();
      } else {
        prodRef = prods.doc(prodId);
        prodSnap = await prodRef.get();
      }

      // 2) Se o produto não existe, abre diálogo padronizado para criá-lo
      if (!prodSnap.exists) {
        final created = await _showCreateProductDialog(
          context: context,
          tenantId: tenantId,
          uid: uid,
          prodRef: prodRef,
          precoSugerido: custo,
        );

        if (!created) {
          // usuário cancelou ou deu erro
          if (mounted) {
            setState(() => _busy = false);
          }
          return;
        }
        // após criar, recarrega o snapshot
        prodSnap = await prodRef.get();
      }

      // 3) Agora o produto existe; registra a entrada + atualiza estoque
      await db.runTransaction((tx) async {
        final snap = await tx.get(prodRef);
        final data = snap.data() ?? {};

        final nome = (data['nome'] as String?) ?? prodId;
        final atual = (data['quantidade'] as int?) ?? 0;

        final novoEstoque = atual + qtd;

        final precoVenda = (data['preco'] as num?)?.toDouble() ??
            (data['precoVenda'] as num?)?.toDouble() ??
            custo;

        // Atualiza produto
        tx.update(prodRef, {
          'quantidade': novoEstoque,
          'preco': precoVenda,
          'precoVenda': precoVenda,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        });

        // Registra o movimento
        final movRef = movs.doc();
        tx.set(movRef, {
          'tipo': 'entrada',
          'quantidade': qtd,
          'produtoId': prodRef.id,
          'produtoNome': nome,
          'usuarioId': uid,
          'preco': custo, // custo unitário informado aqui
          'valorTotal': custo * qtd,
          'motivo': motivo.isEmpty ? 'entrada manual' : motivo,
          'origem': 'manual',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada registrada com sucesso.')),
      );
      Navigator.pop(context);
    } on FirebaseException catch (e) {
      setState(() => _err = '[${e.code}] ${e.message}');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Diálogo padronizado para criar produto quando não existe.
  Future<bool> _showCreateProductDialog({
    required BuildContext context,
    required String tenantId,
    required String uid,
    required DocumentReference<Map<String, dynamic>> prodRef,
    double? precoSugerido,
  }) async {
    final nomeCtrl = TextEditingController();
    final precoCtrl =
        TextEditingController(text: (precoSugerido ?? 0).toStringAsFixed(2));
    final minCtrl = TextEditingController(text: '0');
    final categoriaCtrl = TextEditingController();
    final skuCtrl = TextEditingController();

    String? err;
    bool saving = false;
    bool created = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> save() async {
              if (saving) return;
              setLocal(() {
                err = null;
                saving = true;
              });

              final nome = nomeCtrl.text.trim();
              final min = int.tryParse(minCtrl.text.trim()) ?? 0;
              final preco = _parseDouble(precoCtrl.text);

              if (nome.isEmpty) {
                setLocal(() {
                  err = 'Informe o nome do produto.';
                  saving = false;
                });
                return;
              }

              try {
                final data = <String, dynamic>{
                  'nome': nome,
                  'nomeLower': nome.toLowerCase(),
                  'categoria': categoriaCtrl.text.trim(),
                  'sku': skuCtrl.text.trim(),
                  'preco': preco,
                  'precoVenda': preco,
                  'quantidade': 0,
                  'estoqueMinimo': min,
                  'ativo': true,
                  'createdAt': FieldValue.serverTimestamp(),
                  'createdBy': uid,
                  'updatedAt': FieldValue.serverTimestamp(),
                  'updatedBy': uid,
                };

                await prodRef.set(data);

                created = true;
                if (!context.mounted) return;
                Navigator.pop(context);
              } on FirebaseException catch (e) {
                setLocal(() {
                  err = '${e.code}: ${e.message}';
                  saving = false;
                });
              } catch (e) {
                setLocal(() {
                  err = e.toString();
                  saving = false;
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text('Criar produto\nID: ${prodRef.id}',
                  style: Theme.of(context).textTheme.titleMedium),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nomeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome *',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: precoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Preço de venda *',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: minCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Estoque mínimo',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoriaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Categoria (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: skuCtrl,
                        decoration: const InputDecoration(
                          labelText: 'SKU (opcional)',
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
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Criando...' : 'Criar'),
                ),
              ],
            );
          },
        );
      },
    );

    return created;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrada manual')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              labelText: 'ID do produto (documentId) – opcional',
              hintText: 'Deixe vazio para criar com ID automático',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qtdCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantidade (+)',
              prefixIcon: Icon(Icons.add),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _custoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Custo unitário (opcional)',
              hintText: 'Ex.: 12,34',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoCtrl,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              prefixIcon: Icon(Icons.info_outline),
            ),
          ),
          const SizedBox(height: 16),
          if (_err != null)
            Text(
              _err!,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Salvando...' : 'Salvar'),
          ),
        ],
      ),
    );
  }
}
