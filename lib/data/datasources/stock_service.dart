import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Linhas de venda (saída de estoque)
class SaleLine {
  final String produtoId;
  final int qty;
  final double unitPrice;
  const SaleLine(
      {required this.produtoId, required this.qty, required this.unitPrice});
}

/// Linhas de entrada/compra (entrada de estoque)
class InboundLine {
  final String produtoId;
  final int qty;
  final double unitCost;
  const InboundLine(
      {required this.produtoId, required this.qty, required this.unitCost});
}

class StockService {
  final FirebaseFirestore db;
  final String tenantId;
  StockService(this.db, this.tenantId);

  /// Atualiza somente os campos permitidos nas rules de produtos.
  Future<void> updateProductQty({
    required String productId,
    required int newQty,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .doc(productId)
        .update({
      'quantidade': newQty,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }

  /// Cria uma VENDA em /vendas, gera MOVIMENTOS de 'saida' e aplica a baixa nos produtos.
  /// Tudo em uma única transação para consistência.
  Future<void> createSaleAndApply({
    required List<SaleLine> lines,
    required String usuarioId,
    required double total,
    String? pagamento,
    String origem = 'manual_sale',
  }) async {
    if (lines.isEmpty) throw Exception('Sem itens');

    final vendaRef =
        db.collection('tenants').doc(tenantId).collection('vendas').doc();

    await db.runTransaction((tx) async {
      // 1) lê todos os produtos usados
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prods = {};
      for (final l in lines) {
        final ref = db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .doc(l.produtoId);
        prods[l.produtoId] = await tx.get(ref);
        if (!prods[l.produtoId]!.exists) {
          throw Exception('Produto ${l.produtoId} não encontrado');
        }
      }

      // 2) cria a venda (rules: itens list, subtotal/total number, pagamento string opcional, usuarioId, createdAt)
      tx.set(vendaRef, {
        'itens': [
          for (final l in lines)
            {'produtoId': l.produtoId, 'qty': l.qty, 'unitPrice': l.unitPrice}
        ],
        'subtotal': total, // se tiver descontos, calcule e ajuste
        'total': total,
        'pagamento': (pagamento ?? ''),
        'usuarioId': usuarioId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3) para cada item, cria movimento SAÍDA e atualiza produto
      for (final l in lines) {
        final prodRef = db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .doc(l.produtoId);

        final int atual =
            (prods[l.produtoId]!.data()?['quantidade'] ?? 0) as int;
        final int novo = (atual - l.qty) < 0 ? 0 : (atual - l.qty);

        final movRef = db
            .collection('tenants')
            .doc(tenantId)
            .collection('movimentos')
            .doc();

        tx.set(movRef, {
          'tipo': 'saida',
          'quantidade': l.qty,
          'produtoId': l.produtoId,
          'usuarioId': usuarioId,
          'motivo': 'venda',
          'origem': origem,
          'mensagemOriginal': '',
          'createdAt': FieldValue.serverTimestamp(),
        });

        tx.update(prodRef, {
          'quantidade': novo,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': usuarioId,
        });
      }
    });
  }

  /// Gera movimentos de ENTRADA e atualiza produtos (sem criar documento em /vendas).
  Future<void> createInboundAndApply({
    required List<InboundLine> lines,
    required String usuarioId,
    String origem = 'manual_entry',
    String? motivo,
  }) async {
    if (lines.isEmpty) throw Exception('Sem itens');

    await db.runTransaction((tx) async {
      for (final l in lines) {
        final prodRef = db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .doc(l.produtoId);
        final snap = await tx.get(prodRef);
        if (!snap.exists) {
          throw Exception('Produto ${l.produtoId} não encontrado');
        }
        final int atual = (snap.data()?['quantidade'] ?? 0) as int;
        final int novo = atual + l.qty;

        final movRef = db
            .collection('tenants')
            .doc(tenantId)
            .collection('movimentos')
            .doc();

        tx.set(movRef, {
          'tipo': 'entrada',
          'quantidade': l.qty,
          'produtoId': l.produtoId,
          'usuarioId': usuarioId,
          'motivo': motivo ?? '',
          'origem': origem,
          'mensagemOriginal': '',
          'createdAt': FieldValue.serverTimestamp(),
        });

        tx.update(prodRef, {
          'quantidade': novo,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': usuarioId,
        });
      }
    });
  }

  /// Resumo para a IA responder.
  Future<({int itens, double valor})> getTotals() async {
    final snap = await db
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .get();
    int itens = 0;
    double valor = 0.0;
    for (final d in snap.docs) {
      final q = (d.data()['quantidade'] ?? 0) as int;
      final pAny = d.data()['preco'];
      final p = pAny is num ? pAny.toDouble() : 0.0;
      itens += q;
      valor += q * p;
    }
    return (itens: itens, valor: valor);
  }
}
