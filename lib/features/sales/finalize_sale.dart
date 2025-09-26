// lib/features/sales/finalize_sale.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SaleItem {
  final String produtoId;
  final String nome;
  final int quantidade;
  final double precoUnitario;
  SaleItem({required this.produtoId, required this.nome, required this.quantidade, required this.precoUnitario});
}

Future<void> finalizeSale({
  required String tenantId,
  required String usuarioId,
  required List<SaleItem> itens,
  required String pagamento, // "pix" | "dinheiro" | ...
  double desconto = 0.0,
}) async {
  final db = FirebaseFirestore.instance;
  final batch = db.batch();

  double subtotal = 0;
  for (final it in itens) {
    subtotal += it.precoUnitario * it.quantidade;
  }
  final total = (subtotal - desconto).clamp(0, double.infinity);

  // 1) cria venda
  final vendaRef = db.collection('tenants').doc(tenantId).collection('vendas').doc();
  batch.set(vendaRef, {
    'itens': itens.map((i) => {
      'produtoId': i.produtoId,
      'nome': i.nome,
      'qtd': i.quantidade,
      'preco': i.precoUnitario,
      'totalItem': i.precoUnitario * i.quantidade,
    }).toList(),
    'subtotal': subtotal,
    'desconto': desconto,
    'total': total,
    'pagamento': pagamento,
    'usuarioId': usuarioId,
    'createdAt': FieldValue.serverTimestamp(),
    'status': 'concluida',
  });

  // 2) abate estoque + log de movimento
  for (final it in itens) {
    final prodRef = db.collection('tenants').doc(tenantId).collection('produtos').doc(it.produtoId);
    batch.update(prodRef, {
      'quantidade': FieldValue.increment(-it.quantidade),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final movRef = db.collection('tenants').doc(tenantId).collection('movimentos').doc();
    batch.set(movRef, {
      'produtoId': it.produtoId,
      'tipo': 'saida',
      'quantidade': it.quantidade,
      'motivo': 'venda',
      'usuarioId': usuarioId,
      'origem': 'ui',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
}
