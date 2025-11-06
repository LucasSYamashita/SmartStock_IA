// lib/features/sales/manual_sale_flow.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../tenant/tenant_provider.dart';
import '../../data/datasources/firestore_movements.dart';
import 'package:smartstock_flutter_only/features/sales/sale_success_page.dart';

class ManualSaleCatalogPage extends ConsumerStatefulWidget {
  const ManualSaleCatalogPage({super.key});

  @override
  ConsumerState<ManualSaleCatalogPage> createState() =>
      _ManualSaleCatalogPageState();
}

class _ManualSaleCatalogPageState extends ConsumerState<ManualSaleCatalogPage> {
  final Map<String, int> _cart = {}; // produtoId -> qty
  final Map<String, double> _prices = {}; // produtoId -> preço unitário

  String _paymentMethod = 'pix'; // pix|dinheiro|debito|credito|outros
  final _paymentNote = TextEditingController();
  final _customerName = TextEditingController(); // só no recibo (não salva)

  @override
  void dispose() {
    _paymentNote.dispose();
    _customerName.dispose();
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

    final query = FirebaseFirestore.instance
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
            tooltip: 'Forma de pagamento / Cliente',
            icon: const Icon(Icons.credit_card),
            onPressed: _choosePayment,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
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

              final precoAny = m['preco'] ?? m['valor'] ?? m['precoVenda'] ?? 0;
              final preco = precoAny is num
                  ? precoAny.toDouble()
                  : (double.tryParse('$precoAny') ?? 0.0);
              _prices[id] = preco;

              final q = _cart[id] ?? 0;

              return ListTile(
                onTap: () => _editQtyWithKeyboard(id, nome, q),
                leading: CircleAvatar(
                  child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?'),
                ),
                title: Text(nome),
                subtitle: Text(_fmt(preco)),
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
                    Text('Total: ${_fmt(total)}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Pagamento: ${_paymentMethod.toUpperCase()}'
                      '${_customerName.text.trim().isEmpty ? '' : ' • Cliente: ${_customerName.text.trim()}'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            const Text('Forma de pagamento',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PayChip('PIX', _paymentMethod == 'pix',
                    () => Navigator.pop(context, 'pix')),
                _PayChip('Dinheiro', _paymentMethod == 'dinheiro',
                    () => Navigator.pop(context, 'dinheiro')),
                _PayChip('Débito', _paymentMethod == 'debito',
                    () => Navigator.pop(context, 'debito')),
                _PayChip('Crédito', _paymentMethod == 'credito',
                    () => Navigator.pop(context, 'credito')),
                _PayChip('Outros', _paymentMethod == 'outros',
                    () => Navigator.pop(context, 'outros')),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customerName,
              decoration: const InputDecoration(
                labelText: 'Nome do cliente (opcional – só no recibo)',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _paymentNote,
              decoration: const InputDecoration(
                labelText: 'Observação do pagamento (opcional)',
                prefixIcon: Icon(Icons.note_alt_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _paymentMethod),
                child: const Text('Ok'),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) setState(() => _paymentMethod = selected);
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _cart[id] = v);
  }

  Future<void> _finalizarVenda() async {
    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw StateError('Loja não selecionada.');

      // itens
      final itens = <_SaleLine>[];
      _cart.forEach((id, qty) {
        if (qty > 0) {
          final p = _prices[id] ?? 0.0;
          itens.add(_SaleLine(produtoId: id, qty: qty, unitPrice: p));
        }
      });
      if (itens.isEmpty) throw StateError('Carrinho vazio.');

      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final subtotal =
          itens.fold<double>(0.0, (s, e) => s + e.unitPrice * e.qty);
      final desconto = 0.0;
      final total = (subtotal - desconto).clamp(0.0, double.infinity);

      // 1) cria venda (sem clienteNome; paymentNote só se existir)
      final vendaData = {
        'itens': [
          for (final it in itens)
            {
              'productId': it.produtoId,
              'qtd': it.qty,
              'preco': it.unitPrice,
              'total': it.unitPrice * it.qty,
            }
        ],
        'subtotal': subtotal,
        'desconto': desconto,
        'total': total,
        'pagamento': _paymentMethod,
        'paymentMethod': _paymentMethod,
        'usuarioId': uid,
        'origem': 'venda_manual',
        'createdAt': FieldValue.serverTimestamp(),
        if (_paymentNote.text.trim().isNotEmpty)
          'paymentNote': _paymentNote.text.trim(),
      };

      final vendaRef = await db
          .collection('tenants')
          .doc(tenantId)
          .collection('vendas')
          .add(vendaData);

      // 2) aplica movimentações
      final mov = FirestoreMovements(db, tenantId);
      for (final it in itens) {
        await mov.applyMovement(
          produtoId: it.produtoId,
          tipo: 'saida',
          quantidade: it.qty,
          motivo: 'venda manual',
          usuarioId: uid,
          origem: 'venda_manual',
          mensagemOriginal: 'Venda ${vendaRef.id} • ${it.qty}×',
          paymentMethod: _paymentMethod,
          paymentNote: _paymentNote.text.trim().isEmpty
              ? null
              : _paymentNote.text.trim(),
          preco: it.unitPrice,
        );
      }

      // 3) limpa carrinho
      setState(() {
        _cart.clear();
        _prices.clear();
      });

      // 4) sucesso
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SaleSuccessPage(
            vendaId: vendaRef.id,
            total: total,
            method: _paymentMethod,
            onShare: () => _shareReceipt(
              vendaId: vendaRef.id,
              tenantId: tenantId,
              total: total,
              desconto: desconto,
              itens: itens,
              paymentMethod: _paymentMethod,
              customerName: _customerName.text.trim(),
            ),
          ),
        ),
      );
    } catch (e) {
      final msg = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao finalizar venda: $msg')),
      );
    }
  }

  Future<void> _shareReceipt({
    required String vendaId,
    required String tenantId,
    required double total,
    required double desconto,
    required List<_SaleLine> itens,
    required String paymentMethod,
    String? customerName,
  }) async {
    // loja
    String loja = tenantId;
    try {
      final t = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .get();
      loja = (t.data()?['name'] ?? loja).toString();
    } catch (_) {}

    final subtotal =
        itens.fold<double>(0.0, (s, it) => s + (it.unitPrice * it.qty));
    final b = StringBuffer()
      ..writeln('Recibo – $loja')
      ..writeln('Venda: $vendaId')
      ..writeln('-----------------------------');

    if (customerName != null && customerName.isNotEmpty) {
      b.writeln('Cliente: $customerName');
      b.writeln('-----------------------------');
    }

    for (final it in itens) {
      b.writeln(
          '${it.qty}× @ ${_fmt(it.unitPrice)} = ${_fmt(it.unitPrice * it.qty)}');
    }
    b
      ..writeln('-----------------------------')
      ..writeln('Subtotal: ${_fmt(subtotal)}')
      ..writeln('Desconto: ${_fmt(desconto)}')
      ..writeln('Total:    ${_fmt(total)}')
      ..writeln('Pagamento: ${paymentMethod.toUpperCase()}');

    try {
      await Share.share(b.toString());
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: b.toString()));
    }
  }
}

class _PayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PayChip(this.label, this.selected, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _SaleLine {
  final String produtoId;
  final int qty;
  final double unitPrice;
  _SaleLine(
      {required this.produtoId, required this.qty, required this.unitPrice});
}

String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
