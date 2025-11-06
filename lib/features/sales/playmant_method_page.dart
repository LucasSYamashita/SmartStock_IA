import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smartstock_flutter_only/features/sales/cart_state.dart';
import 'sale_receipt_page.dart';

String _fmtBR(double v) => 'R\$ ' + v.toStringAsFixed(2).replaceAll('.', ',');

enum PaymentMethod { pix, credito, debito, dinheiro, boleto }

String _pmLabel(PaymentMethod m) {
  switch (m) {
    case PaymentMethod.pix:
      return 'PIX';
    case PaymentMethod.credito:
      return 'Crédito';
    case PaymentMethod.debito:
      return 'Débito';
    case PaymentMethod.dinheiro:
      return 'Dinheiro';
    case PaymentMethod.boleto:
      return 'Boleto';
  }
}

class PaymentMethodPage extends StatefulWidget {
  final String tenantId;
  final List<CartItem> items;
  final VoidCallback onClearCart; // limpar carrinho depois de concluir

  const PaymentMethodPage({
    super.key,
    required this.tenantId,
    required this.items,
    required this.onClearCart,
  });

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  PaymentMethod _method = PaymentMethod.pix;
  final _customerCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  double get total =>
      widget.items.fold(0.0, (acc, e) => acc + (e.unitPrice * e.quantity));

  @override
  void dispose() {
    _customerCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _finalize() async {
    if (_saving) return;
    setState(() => _saving = true);

    final user = FirebaseAuth.instance.currentUser!;
    final db = FirebaseFirestore.instance;

    final vendasCol =
        db.collection('tenants').doc(widget.tenantId).collection('vendas');

    final movimentosCol =
        db.collection('tenants').doc(widget.tenantId).collection('movimentos');

    final produtosCol =
        db.collection('tenants').doc(widget.tenantId).collection('produtos');

    // Observação importante (compatível com suas regras):
    // /vendas aceita: total, usuarioId, origem, createdAt, paymentMethod, paymentNote
    // (não grava itens/desconto aqui — os itens ficam nos movimentos)
    final batch = db.batch();
    final vendaRef = vendasCol.doc(); // id conhecido

    batch.set(vendaRef, {
      'total': total,
      'usuarioId': user.uid,
      'origem': 'app',
      'createdAt': FieldValue.serverTimestamp(),
      'paymentMethod': _pmLabel(_method),
      'paymentNote': _noteCtrl.text.trim().isNotEmpty
          ? _noteCtrl.text.trim()
          : (_customerCtrl.text.trim().isNotEmpty
              ? 'Cliente: ${_customerCtrl.text.trim()}'
              : null),
    });

    for (final it in widget.items) {
      // Movimento idempotente por venda+produto
      final movRef = movimentosCol.doc('${vendaRef.id}_${it.productId}');
      batch.set(movRef, {
        'tipo': 'saida',
        'produtoId': it.productId,
        'produtoNome': it.nome,
        'quantidade': it.quantity,
        'preco': it.unitPrice,
        'usuarioId': user.uid,
        'origem': 'sale',
        'motivo': 'venda ${vendaRef.id}',
        'requestId': '${vendaRef.id}_${it.productId}',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Atualiza estoque
      batch.update(produtosCol.doc(it.productId), {
        'quantidade': FieldValue.increment(-it.quantity),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });
    }

    try {
      await batch.commit();

      // Texto do comprovante
      final receipt = _buildReceiptText(
        vendaId: vendaRef.id,
        tenantId: widget.tenantId,
        items: widget.items,
        total: total,
        method: _pmLabel(_method),
        customer: _customerCtrl.text.trim().isEmpty
            ? null
            : _customerCtrl.text.trim(),
        sellerUid: user.uid,
      );

      // Limpa carrinho
      widget.onClearCart();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SaleReceiptPage(receiptText: receipt),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao finalizar: ${e.message ?? e.code}')),
      );
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao finalizar: $e')),
      );
      setState(() => _saving = false);
    }
  }

  String _buildReceiptText({
    required String vendaId,
    required String tenantId,
    required List<CartItem> items,
    required double total,
    required String method,
    String? customer,
    required String sellerUid,
  }) {
    final now = DateTime.now();
    final data =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final sb = StringBuffer();
    sb.writeln('SmartStock – Comprovante de Venda');
    sb.writeln('Loja: $tenantId');
    sb.writeln('Venda: $vendaId');
    sb.writeln('Data: $data');
    if (customer != null && customer.isNotEmpty) {
      sb.writeln('Cliente: $customer');
    }
    sb.writeln('');
    for (final it in items) {
      final sub = it.unitPrice * it.quantity;
      sb.writeln(
          '${it.nome}  x${it.quantity}  ${_fmtBR(it.unitPrice)}  = ${_fmtBR(sub)}');
    }
    sb.writeln('----------------------------');
    sb.writeln('Total: ${_fmtBR(total)}');
    sb.writeln('Pagamento: $method');
    sb.writeln('');
    sb.writeln('Vendedor: $sellerUid');
    sb.writeln('Obrigado pela preferência!');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      appBar: AppBar(title: const Text('Método de pagamento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Resumo',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  ...items.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.nome),
                        subtitle:
                            Text('x${e.quantity} · ${_fmtBR(e.unitPrice)}'),
                        trailing: Text(
                          _fmtBR(e.unitPrice * e.quantity),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: ${_fmtBR(total)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                RadioListTile<PaymentMethod>(
                  title: const Text('PIX'),
                  value: PaymentMethod.pix,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
                RadioListTile<PaymentMethod>(
                  title: const Text('Crédito'),
                  value: PaymentMethod.credito,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
                RadioListTile<PaymentMethod>(
                  title: const Text('Débito'),
                  value: PaymentMethod.debito,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
                RadioListTile<PaymentMethod>(
                  title: const Text('Dinheiro'),
                  value: PaymentMethod.dinheiro,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
                RadioListTile<PaymentMethod>(
                  title: const Text('Boleto'),
                  value: PaymentMethod.boleto,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customerCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome do cliente (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Observação do pagamento (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _finalize,
            icon: const Icon(Icons.check),
            label: Text(_saving ? 'Finalizando...' : 'Finalizar venda'),
          ),
        ],
      ),
    );
  }
}
