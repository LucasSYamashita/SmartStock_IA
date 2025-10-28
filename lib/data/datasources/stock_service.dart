// lib/data/datasources/stock_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SaleLine {
  final String produtoId;
  final int qty;
  final double unitPrice;
  const SaleLine({
    required this.produtoId,
    required this.qty,
    required this.unitPrice,
  });
}

class InboundLine {
  final String produtoId;
  final int qty;
  final double unitCost;
  const InboundLine({
    required this.produtoId,
    required this.qty,
    required this.unitCost,
  });
}

class StockService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// VENDA (baixa estoque + grava movimento + grava documento de venda)
  static Future<void> createSaleAndApply({
    required String tenantId,
    required List<SaleLine> lines,
    required String paymentMethod, // 'PIX'|'Crédito'|'Débito'|'Dinheiro'|etc
    String paymentNote = '',
    String origem = 'app',
  }) async {
    final tenantRef = _db.collection('tenants').doc(tenantId);
    final produtosCol = tenantRef.collection('produtos');
    final movimentosCol = tenantRef.collection('movimentos');
    final vendasCol = tenantRef.collection('vendas');

    await _db.runTransaction((tx) async {
      double total = 0;

      for (final l in lines) {
        final prodRef = produtosCol.doc(l.produtoId);
        final snap = await tx.get(prodRef);
        if (!snap.exists) {
          throw StateError('Produto não encontrado: ${l.produtoId}');
        }

        final data = snap.data() as Map<String, dynamic>;
        final nome = (data['nome'] ?? '').toString();
        final qtdAtualAny = data['quantidade'] ?? 0;
        final qtdAtual = qtdAtualAny is num
            ? qtdAtualAny.toInt()
            : int.tryParse('$qtdAtualAny') ?? 0;

        final novoSaldo = qtdAtual - l.qty;
        if (novoSaldo < 0) {
          throw StateError('Estoque insuficiente para $nome');
        }

        tx.update(prodRef, {
          'quantidade': novoSaldo,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _uid,
        });

        tx.set(movimentosCol.doc(), {
          'produtoId': l.produtoId,
          'produtoNome': nome,
          'tipo': 'saida',
          'quantidade': l.qty,
          'motivo': 'venda',
          'origem': origem,
          'usuarioId': _uid,
          'paymentMethod': paymentMethod,
          if (paymentNote.isNotEmpty) 'paymentNote': paymentNote,
          'createdAt': FieldValue.serverTimestamp(),
        });

        total += l.qty * l.unitPrice;
      }

      tx.set(vendasCol.doc(), {
        'total': total,
        'usuarioId': _uid,
        'origem': origem,
        'paymentMethod': paymentMethod,
        if (paymentNote.isNotEmpty) 'paymentNote': paymentNote,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// ENTRADA (reposição) + grava movimento
  static Future<void> createInboundAndApply({
    required String tenantId,
    required List<InboundLine> lines,
    String motivo = 'compra',
    String origem = 'app',
  }) async {
    final tenantRef = _db.collection('tenants').doc(tenantId);
    final produtosCol = tenantRef.collection('produtos');
    final movimentosCol = tenantRef.collection('movimentos');

    await _db.runTransaction((tx) async {
      for (final l in lines) {
        final prodRef = produtosCol.doc(l.produtoId);
        final snap = await tx.get(prodRef);
        if (!snap.exists) {
          throw StateError('Produto não encontrado: ${l.produtoId}');
        }

        final data = snap.data() as Map<String, dynamic>;
        final nome = (data['nome'] ?? '').toString();
        final qtdAtualAny = data['quantidade'] ?? 0;
        final qtdAtual = qtdAtualAny is num
            ? qtdAtualAny.toInt()
            : int.tryParse('$qtdAtualAny') ?? 0;

        tx.update(prodRef, {
          'quantidade': qtdAtual + l.qty,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _uid,
        });

        tx.set(movimentosCol.doc(), {
          'produtoId': l.produtoId,
          'produtoNome': nome,
          'tipo': 'entrada',
          'quantidade': l.qty,
          'motivo': motivo,
          'origem': origem,
          'usuarioId': _uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
