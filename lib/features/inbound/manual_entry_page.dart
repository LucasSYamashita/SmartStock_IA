import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';
import '../../data/datasources/stock_service.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});
  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _produtoId = TextEditingController();
  final _qtd = TextEditingController(text: '1');
  final _valor = TextEditingController(text: '0');

  @override
  void dispose() {
    _produtoId.dispose();
    _qtd.dispose();
    _valor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrada manual')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _produtoId,
              decoration: const InputDecoration(
                labelText: 'ID do produto (documentId)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qtd,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantidade (+)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _valor,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Custo unitário (opcional)'),
            ),
            const Spacer(),
            SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _salvar,
                  child: const Text('Salvar'),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _salvar() async {
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

    final id = _produtoId.text.trim();
    final qtd = int.tryParse(_qtd.text.trim()) ?? 0;
    final custo =
        double.tryParse(_valor.text.trim().replaceAll(',', '.')) ?? 0.0;

    if (id.isEmpty || qtd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha produto e quantidade > 0.')),
      );
      return;
    }

    try {
      await service.createInboundAndApply(
        lines: [InboundLine(produtoId: id, qty: qtd, unitCost: custo)],
        usuarioId: uid,
        origem: 'manual_entry',
        motivo: 'entrada manual',
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada registrada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }
}
