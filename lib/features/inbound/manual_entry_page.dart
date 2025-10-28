// lib/features/inbound/manual_entry_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smartstock_flutter_only/features/tenant/tenant_provider.dart';
import 'package:smartstock_flutter_only/data/datasources/stock_service.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  /// Se for chamada a partir da tela de detalhes de um produto,
  /// você pode passar o [produtoId] para já preencher.
  final String? produtoId;
  const ManualEntryPage({super.key, this.produtoId});

  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _produtoIdCtrl = TextEditingController();
  final _qtdCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController(text: '0');
  final _motivoCtrl = TextEditingController(text: 'compra');

  @override
  void initState() {
    super.initState();
    if (widget.produtoId != null) {
      _produtoIdCtrl.text = widget.produtoId!;
    }
  }

  @override
  void dispose() {
    _produtoIdCtrl.dispose();
    _qtdCtrl.dispose();
    _costCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Entrada manual')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _produtoIdCtrl,
            decoration: const InputDecoration(
              labelText: 'ID do produto (documentId)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qtdCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Quantidade (+)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Custo unitário (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoCtrl,
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: tenantId == null ? null : _salvar,
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _salvar() async {
    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw StateError('Loja não selecionada.');

      final produtoId = _produtoIdCtrl.text.trim();
      final qtd = int.tryParse(_qtdCtrl.text.trim()) ?? 0;
      final custo = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0;
      final motivo =
          _motivoCtrl.text.trim().isEmpty ? 'compra' : _motivoCtrl.text.trim();

      if (produtoId.isEmpty || qtd <= 0) {
        throw StateError('Informe ID do produto e quantidade > 0.');
      }

      await StockService.createInboundAndApply(
        tenantId: tenantId,
        lines: [InboundLine(produtoId: produtoId, qty: qtd, unitCost: custo)],
        motivo: motivo,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada registrada.')),
      );
      Navigator.pop(context);
    } catch (e) {
      final msg = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $msg')),
      );
    }
  }
}
