import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../tenant/tenant_provider.dart';
import 'cart_state.dart';
import 'manual_sale_page.dart' show _fmt;
import 'sale_success_page.dart';
import '../../data/datasources/firestore_movements.dart';

class ManualSaleCheckoutPage extends ConsumerStatefulWidget {
  final bool focusDiscount;
  const ManualSaleCheckoutPage({super.key, this.focusDiscount = false});

  @override
  ConsumerState<ManualSaleCheckoutPage> createState() =>
      _ManualSaleCheckoutPageState();
}

class _ManualSaleCheckoutPageState
    extends ConsumerState<ManualSaleCheckoutPage> {
  // pagamento
  String method = 'dinheiro'; // dinheiro, debito, credito, pix, outros
  // desconto
  bool percent = false;
  final _discountCtrl = TextEditingController();
  // cliente opcional
  final _clienteCtrl = TextEditingController();

  bool saving = false;
  String? err;

  @override
  void initState() {
    super.initState();
    if (widget.focusDiscount) {
      // foca no campo após renderizar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_discountFocusNode);
      });
    }
  }

  final _discountFocusNode = FocusNode();

  @override
  void dispose() {
    _discountCtrl.dispose();
    _clienteCtrl.dispose();
    _discountFocusNode.dispose();
    super.dispose();
  }

  double _parseDiscount() {
    final raw = _discountCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final d = _parseDiscount();
    final descontoBruto = percent ? subtotal * (d / 100.0) : d;
    final desconto = descontoBruto.clamp(0.0, subtotal).toDouble();
    final double total =
        (subtotal - desconto).clamp(0.0, double.infinity).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Pagamento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // total+cliente
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_fmt(total),
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clienteCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Cliente (opcional)',
                      hintText: 'Ex.: João da Silva',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // grid métodos de pagamento
          _PaymentGrid(
            current: method,
            onChanged: (m) => setState(() => method = m),
          ),
          const SizedBox(height: 12),

          // desconto
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _discountFocusNode,
                      controller: _discountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'))
                      ],
                      decoration: InputDecoration(
                        labelText: percent ? 'Desconto (%)' : 'Desconto (R\$)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('R\$')),
                      ButtonSegment(value: true, label: Text('%')),
                    ],
                    selected: {percent},
                    onSelectionChanged: (s) =>
                        setState(() => percent = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // resumo itens
          ExpansionTile(
            title: const Text('Itens da venda'),
            children: [
              for (final it in items)
                ListTile(
                  title: Text(it.nome),
                  subtitle: Text('${it.quantity} × ${_fmt(it.unitPrice)}'),
                  trailing: Text(_fmt(it.total)),
                ),
              const SizedBox(height: 8),
            ],
          ),

          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),

          FilledButton(
            onPressed: saving || items.isEmpty
                ? null
                : () => _finalizar(total, desconto, List<CartItem>.from(items)),
            child: Text(saving ? 'Finalizando...' : 'Avançar'),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizar(
      double total, double desconto, List<CartItem> items) async {
    setState(() {
      saving = true;
      err = null;
    });

    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw Exception('Loja não definida.');
      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final subtotal = items.fold<double>(0.0, (s, it) => s + it.total);

      // 1) registra venda
      final vendaRef = await db
          .collection('tenants')
          .doc(tenantId)
          .collection('vendas')
          .add({
        'cliente':
            _clienteCtrl.text.trim().isEmpty ? null : _clienteCtrl.text.trim(),
        'itens': [
          for (final it in items)
            {
              'productId': it.productId,
              'nome': it.nome,
              'qtd': it.quantity,
              'preco': it.unitPrice,
              'total': it.total,
            }
        ],
        'subtotal': subtotal,
        'desconto': desconto,
        'total': total,
        'pagamento': method,
        'usuarioId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) baixa do estoque + log (com paymentMethod)
      final mov = FirestoreMovements(db, tenantId);
      for (final it in items) {
        await mov.applyMovement(
          produtoId: it.productId,
          tipo: 'saida',
          quantidade: it.quantity,
          motivo: 'venda',
          usuarioId: uid,
          origem: 'venda_manual',
          mensagemOriginal: 'Venda ${vendaRef.id} • ${it.quantity}× ${it.nome}',
          paymentMethod: method, // << NOVO
        );
      }

      // 3) limpa carrinho
      ref.read(cartProvider.notifier).clear();

      // 4) recibo e sucesso
      final recibo = await _buildReceiptText(
        vendaId: vendaRef.id,
        total: total,
        desconto: desconto,
        items: items,
        paymentMethod: method,
        tenantId: tenantId,
        cliente: _clienteCtrl.text.trim(),
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SaleSuccessPage(
            total: total,
            recibo: recibo,
            onShare: () async => Share.share(recibo),
          ),
        ),
      );
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<String> _buildReceiptText({
    required String vendaId,
    required double total,
    required double desconto,
    required List<CartItem> items,
    required String paymentMethod,
    required String tenantId,
    String? cliente,
  }) async {
    String loja = 'SmartStock';
    try {
      final t = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .get();
      loja = (t.data()?['name'] ?? loja).toString();
    } catch (_) {}

    final subtotal = items.fold<double>(0.0, (s, it) => s + it.total);
    final b = StringBuffer()
      ..writeln('Recibo – $loja')
      ..writeln('Venda: $vendaId')
      ..writeln('-----------------------------');
    if ((cliente ?? '').isNotEmpty) b.writeln('Cliente: $cliente\n');

    for (final it in items) {
      b.writeln(
          '${it.quantity}× ${it.nome} @ ${_fmt(it.unitPrice)} = ${_fmt(it.total)}');
    }
    b
      ..writeln('-----------------------------')
      ..writeln('Subtotal: ${_fmt(subtotal)}')
      ..writeln('Desconto: ${_fmt(desconto)}')
      ..writeln('Total:    ${_fmt(total)}')
      ..writeln('Pagamento: ${paymentMethod.toUpperCase()}');

    return b.toString();
  }
}

class _PaymentGrid extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _PaymentGrid({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = [
      ('dinheiro', Icons.payments_outlined, 'Dinheiro'),
      ('debito', Icons.credit_card, 'Cartão de Débito'),
      ('credito', Icons.credit_score, 'Cartão de Crédito'),
      ('pix', Icons.qr_code, 'Pix'),
      ('outros', Icons.more_horiz, 'Outros'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in opts)
              ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(o.$2, size: 18),
                  const SizedBox(width: 6),
                  Text(o.$3),
                ]),
                selected: current == o.$1,
                onSelected: (_) => onChanged(o.$1),
              ),
          ],
        ),
      ),
    );
  }
}
