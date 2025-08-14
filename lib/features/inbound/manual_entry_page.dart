import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';
import '../../data/datasources/firestore_movements.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});
  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _nome = TextEditingController();
  final _qtd = TextEditingController(text: '0');
  final _min = TextEditingController(text: '0');
  final _valor = TextEditingController(text: '0');
  final _marca = TextEditingController();

  bool working = false;
  String? err, ok;

  @override
  void dispose() {
    _nome.dispose();
    _qtd.dispose();
    _min.dispose();
    _valor.dispose();
    _marca.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      working = true;
      err = null;
      ok = null;
    });
    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw Exception('Loja não definida.');
      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final nome = _nome.text.trim();
      final qtd = int.tryParse(_qtd.text.trim()) ?? 0;
      final min = int.tryParse(_min.text.trim()) ?? 0;
      final valor =
          double.tryParse(_valor.text.trim().replaceAll(',', '.')) ?? 0.0;
      final marca = _marca.text.trim();

      if (nome.isEmpty || qtd <= 0) {
        setState(() => err = 'Informe nome e quantidade (> 0).');
        return;
      }

      // tenta achar pelo nomeLower
      final q = await db
          .collection('tenants')
          .doc(tenantId)
          .collection('produtos')
          .where('nomeLower', isEqualTo: nome.toLowerCase())
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        // cria produto novo
        final prodRef = await db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .add({
          'nome': nome,
          'nomeLower': nome.toLowerCase(),
          'quantidade': qtd,
          'estoqueMinimo': min,
          'valor': valor,
          'marca': marca.isEmpty ? null : marca,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // registra movimentação
        final mov = FirestoreMovements(db, tenantId);
        await mov.applyMovement(
          produtoId: prodRef.id,
          tipo: 'entrada',
          quantidade: qtd,
          motivo: 'entrada manual (novo)',
          usuarioId: uid,
          origem: 'manual_entry',
          mensagemOriginal: 'Entrada manual de $qtd × $nome (novo)',
        );
      } else {
        // atualiza produto existente (incremento de quantidade)
        final doc = q.docs.first;
        await db.runTransaction((tx) async {
          final snap = await tx.get(doc.reference);
          final cur = (snap.data()?['quantidade'] ?? 0) as num;
          tx.update(doc.reference, {
            'quantidade': (cur.toInt() + qtd),
            'estoqueMinimo': min,
            'valor': valor,
            'marca': marca.isEmpty ? null : marca,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });

        // movimentação
        final mov = FirestoreMovements(db, tenantId);
        await mov.applyMovement(
          produtoId: doc.id,
          tipo: 'entrada',
          quantidade: qtd,
          motivo: 'entrada manual',
          usuarioId: uid,
          origem: 'manual_entry',
          mensagemOriginal: 'Entrada manual de $qtd × $nome',
        );
      }

      setState(() {
        ok = 'Entrada registrada.';
      });
      _nome.clear();
      _qtd.text = '0';
      _min.text = '0';
      _valor.text = '0';
      _marca.clear();
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
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
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 8),
          TextField(
              controller: _qtd,
              decoration: const InputDecoration(labelText: 'Quantidade'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(
              controller: _min,
              decoration: const InputDecoration(labelText: 'Quantidade mínima'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(
              controller: _valor,
              decoration: const InputDecoration(labelText: 'Valor (R\$)'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(
              controller: _marca,
              decoration: const InputDecoration(labelText: 'Marca (opcional)')),
          const SizedBox(height: 12),
          if (err != null)
            Text(err!, style: const TextStyle(color: Colors.red)),
          if (ok != null)
            Text(ok!, style: const TextStyle(color: Colors.green)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: working ? null : _salvar,
              child: Text(working ? 'Salvando...' : 'Registrar entrada'),
            ),
          ),
        ],
      ),
    );
  }
}
