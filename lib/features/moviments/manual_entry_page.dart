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
  final _nameCtrl = TextEditingController(); // usado se produto novo
  final _qtdCtrl = TextEditingController(text: '1');
  final _custoCtrl = TextEditingController(text: '0');
  final _motivoCtrl = TextEditingController(text: 'compra');

  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
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
    final nomeDigitado = _nameCtrl.text.trim();
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

      // gera docId se não informado
      if (prodId.isEmpty) {
        prodId = prods.doc().id;
      }

      final prodRef = prods.doc(prodId);
      final movRef = movs.doc();

      await db.runTransaction((tx) async {
        final snap = await tx.get(prodRef);

        // Se não existir, cria com estrutura mínima (bate regras de CREATE)
        if (!snap.exists) {
          final nome = (nomeDigitado.isNotEmpty ? nomeDigitado : prodId);
          tx.set(prodRef, {
            'nome': nome,
            'nomeLower': nome.toLowerCase(),
            'categoria': '',
            'sku': '',
            'precoVenda': 0, // ter ao menos um preço >=0
            'quantidade': 0,
            'estoqueMinimo': 1,
            'ativo': true,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
          });
        }

        // Nome para o movimento (se já existir, usa o do banco)
        String nomeMov = nomeDigitado;
        final afterGet = await tx.get(prodRef);
        final data = afterGet.data();
        if (data != null &&
            data['nome'] is String &&
            (data['nome'] as String).isNotEmpty) {
          nomeMov = data['nome'] as String;
        }
        if (nomeMov.isEmpty) nomeMov = prodId;

        // Atualiza estoque (PATCH permitido nas rules)
        tx.update(prodRef, {
          'quantidade': FieldValue.increment(qtd),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        });

        // Registra o movimento
        tx.set(movRef, {
          'tipo': 'entrada',
          'quantidade': qtd,
          'produtoId': prodId,
          'produtoNome': nomeMov,
          'usuarioId': uid,
          'preco': custo, // custo unitário (opcional nas rules)
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
              labelText: 'ID do produto (documentId)',
              hintText: 'Deixe em branco para gerar automaticamente',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome do produto (usado se criar novo)',
              prefixIcon: Icon(Icons.inventory_2_outlined),
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
            Text(_err!, style: const TextStyle(color: Colors.red)),
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
