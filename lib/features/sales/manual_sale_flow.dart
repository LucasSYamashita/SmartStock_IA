// lib/features/sales/manual_sale_flow.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smartstock_flutter_only/features/tenant/tenant_provider.dart';
import 'package:smartstock_flutter_only/data/datasources/stock_service.dart';

class ManualSaleCatalogPage extends ConsumerStatefulWidget {
  const ManualSaleCatalogPage({super.key});

  @override
  ConsumerState<ManualSaleCatalogPage> createState() =>
      _ManualSaleCatalogPageState();
}

class _ManualSaleCatalogPageState extends ConsumerState<ManualSaleCatalogPage> {
  final Map<String, int> _cart = {}; // produtoId -> qty
  final Map<String, double> _prices = {}; // produtoId -> preco
  String _paymentMethod = 'PIX';
  final _paymentNote = TextEditingController();

  @override
  void dispose() {
    _paymentNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(
        body: Center(child: Text('Selecione uma loja.')),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .orderBy('nomeLower');

    final total = _cart.entries.fold<double>(
      0,
      (sum, e) => sum + (_prices[e.key] ?? 0.0) * e.value,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vender'),
        actions: [
          IconButton(
            tooltip: 'Forma de pagamento',
            icon: const Icon(Icons.credit_card),
            onPressed: _choosePayment,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Theme.of(context).dividerColor),
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();
              final id = d.id;
              final nome = (m['nome'] ?? '').toString();
              final precoAny = m['preco'] ?? m['valor'] ?? 0;
              final preco = precoAny is num
                  ? precoAny.toDouble()
                  : double.tryParse('$precoAny') ?? 0.0;
              _prices[id] = preco;

              final q = _cart[id] ?? 0;

              return ListTile(
                onTap: () => _editQtyWithKeyboard(id, nome, q),
                leading: CircleAvatar(
                  child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?'),
                ),
                title: Text(nome),
                subtitle: Text('R\$ ${preco.toStringAsFixed(2)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Diminuir',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: q <= 0
                          ? null
                          : () => setState(() => _cart[id] = q - 1),
                    ),
                    Text('$q', style: const TextStyle(fontSize: 16)),
                    IconButton(
                      tooltip: 'Aumentar',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _cart[id] = q + 1),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total: R\$ ${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text('Pagamento: $_paymentMethod',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Finalizar'),
                onPressed: total <= 0 ? null : _finalizarVenda,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choosePayment() async {
    final methods = ['PIX', 'Crédito', 'Débito', 'Dinheiro', 'Outro'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final m in methods)
            ListTile(
              title: Text(m),
              onTap: () => Navigator.pop(context, m),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _paymentNote,
              decoration:
                  const InputDecoration(labelText: 'Observação do pagamento'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (selected != null) {
      setState(() => _paymentMethod = selected);
    }
  }

  Future<void> _editQtyWithKeyboard(String id, String nome, int current) async {
    final c = TextEditingController(text: '$current');
    final v = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Quantidade · $nome'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(
              signed: false, decimal: false),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: 'Ex.: 3'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                final n = int.tryParse(c.text.trim()) ?? current;
                Navigator.pop(context, n < 0 ? 0 : n);
              },
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null) {
      setState(() => _cart[id] = v);
    }
  }

  Future<void> _finalizarVenda() async {
    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) {
        throw StateError('Loja não selecionada.');
      }

      final lines = <SaleLine>[];
      _cart.forEach((id, qty) {
        if (qty > 0) {
          final p = _prices[id] ?? 0.0;
          lines.add(SaleLine(produtoId: id, qty: qty, unitPrice: p));
        }
      });
      if (lines.isEmpty) throw StateError('Carrinho vazio.');

      await StockService.createSaleAndApply(
        tenantId: tenantId,
        lines: lines,
        paymentMethod: _paymentMethod,
        paymentNote: _paymentNote.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda finalizada!')),
      );
      Navigator.pop(context);
    } catch (e) {
      final msg = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao finalizar venda: $msg')),
      );
    }
  }
}
