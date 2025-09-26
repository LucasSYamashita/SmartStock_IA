import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class SaleLine {
  final String produtoId;
  final int qty;
  final double? unitPrice;
  const SaleLine({required this.produtoId, required this.qty, this.unitPrice});
}

class InboundLine {
  final String produtoId;
  final int qty;
  final double? unitCost;
  const InboundLine({
    required this.produtoId,
    required this.qty,
    this.unitCost,
  });
}

/// Serviço de estoque: aplica entrada, saída (venda) e ajuste dentro de transações.
class StockService {
  final FirebaseFirestore db;
  final String tenantId;
  StockService(this.db, this.tenantId);

  CollectionReference<Map<String, dynamic>> get _prodCol =>
      db.collection('tenants').doc(tenantId).collection('produtos');
  CollectionReference<Map<String, dynamic>> get _movCol =>
      db.collection('tenants').doc(tenantId).collection('movimentos');
  CollectionReference<Map<String, dynamic>> get _saleCol =>
      db.collection('tenants').doc(tenantId).collection('vendas');
  CollectionReference<Map<String, dynamic>> get _inCol =>
      db.collection('tenants').doc(tenantId).collection('entradas');
  CollectionReference<Map<String, dynamic>> get _alertCol =>
      db.collection('tenants').doc(tenantId).collection('alertas');

  /// VENDA (saída)
  Future<void> createSaleAndApply({
    required List<SaleLine> lines,
    required String usuarioId,
    num? total,
    String origem = 'app',
  }) async {
    assert(lines.isNotEmpty, 'Precisa de ao menos 1 item');
    await db.runTransaction((tx) async {
      final now = FieldValue.serverTimestamp();
      final saleRef = _saleCol.doc();
      final itemsDoc = <Map<String, dynamic>>[];

      for (final it in lines) {
        final prodRef = _prodCol.doc(it.produtoId);
        final pSnap = await tx.get(prodRef);
        if (!pSnap.exists)
          throw Exception('Produto não encontrado: ${it.produtoId}');
        final data = pSnap.data()!;
        final qAny = data['quantidade'] ?? 0;
        final minAny = data['estoqueMinimo'] ?? 0;
        final cur = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;
        final min = minAny is num
            ? minAny.toInt()
            : int.tryParse('$minAny') ?? 0;

        final saida = max(0, it.qty);
        final depois = max(0, cur - saida);

        tx.update(prodRef, {'quantidade': depois, 'updatedAt': now});

        final movRef = _movCol.doc();
        tx.set(movRef, {
          'produtoId': it.produtoId,
          'tipo': 'saida',
          'quantidade': saida,
          'motivo': 'venda',
          'origem': origem,
          'usuarioId': usuarioId,
          'mensagemOriginal': 'Venda ${saleRef.id}',
          'createdAt': now,
          'snapshot': {'antes': cur, 'depois': depois},
        });

        if ((cur > min && depois <= min) || depois == 0) {
          final alertRef = _alertCol.doc();
          tx.set(alertRef, {
            'produtoId': it.produtoId,
            'tipo': (depois == 0 ? 'sem_estoque' : 'baixo_estoque'),
            'quantidade': depois,
            'minimo': min,
            'createdAt': now,
          });
        }

        itemsDoc.add({
          'produtoId': it.produtoId,
          'qty': saida,
          if (it.unitPrice != null) 'unitPrice': it.unitPrice,
        });
      }

      tx.set(saleRef, {
        'items': itemsDoc,
        if (total != null) 'total': (total as num).toDouble(),
        'usuarioId': usuarioId,
        'origem': origem,
        'createdAt': now,
        'applied': true,
        'appliedAt': now,
      });
    });
  }

  /// ENTRADA
  Future<void> createInboundAndApply({
    required List<InboundLine> lines,
    required String usuarioId,
    String motivo = 'entrada',
    String origem = 'app',
  }) async {
    assert(lines.isNotEmpty, 'Precisa de ao menos 1 item');
    await db.runTransaction((tx) async {
      final now = FieldValue.serverTimestamp();
      final entryRef = _inCol.doc();
      final itemsDoc = <Map<String, dynamic>>[];

      for (final it in lines) {
        final prodRef = _prodCol.doc(it.produtoId);
        final pSnap = await tx.get(prodRef);
        if (!pSnap.exists)
          throw Exception('Produto não encontrado: ${it.produtoId}');
        final data = pSnap.data()!;
        final qAny = data['quantidade'] ?? 0;
        final cur = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;

        final entrada = max(0, it.qty);
        final depois = cur + entrada;

        tx.update(prodRef, {'quantidade': depois, 'updatedAt': now});

        final movRef = _movCol.doc();
        tx.set(movRef, {
          'produtoId': it.produtoId,
          'tipo': 'entrada',
          'quantidade': entrada,
          'motivo': motivo,
          'origem': origem,
          'usuarioId': usuarioId,
          'mensagemOriginal': 'Entrada ${entryRef.id}',
          'createdAt': now,
          'snapshot': {'antes': cur, 'depois': depois},
        });

        itemsDoc.add({
          'produtoId': it.produtoId,
          'qty': entrada,
          if (it.unitCost != null) 'unitCost': it.unitCost,
        });
      }

      tx.set(entryRef, {
        'items': itemsDoc,
        'usuarioId': usuarioId,
        'motivo': motivo,
        'origem': origem,
        'createdAt': now,
        'applied': true,
        'appliedAt': now,
      });
    });
  }

  /// AJUSTE (+ soma, - subtrai)
  Future<void> adjustStock({
    required String produtoId,
    required int delta,
    required String usuarioId,
    String motivo = 'ajuste',
    String origem = 'app',
  }) async {
    if (delta == 0) return;
    await db.runTransaction((tx) async {
      final now = FieldValue.serverTimestamp();
      final prodRef = _prodCol.doc(produtoId);
      final pSnap = await tx.get(prodRef);
      if (!pSnap.exists) throw Exception('Produto não encontrado');
      final data = pSnap.data()!;
      final qAny = data['quantidade'] ?? 0;
      final minAny = data['estoqueMinimo'] ?? 0;
      final cur = qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;
      final min = minAny is num ? minAny.toInt() : int.tryParse('$minAny') ?? 0;

      final depois = max(0, cur + delta);
      final tipo = delta >= 0 ? 'entrada' : 'saida';
      final qtd = delta.abs();

      tx.update(prodRef, {'quantidade': depois, 'updatedAt': now});

      final movRef = _movCol.doc();
      tx.set(movRef, {
        'produtoId': produtoId,
        'tipo': tipo,
        'quantidade': qtd,
        'motivo': motivo,
        'origem': origem,
        'usuarioId': usuarioId,
        'mensagemOriginal': 'Ajuste manual',
        'createdAt': now,
        'snapshot': {'antes': cur, 'depois': depois},
      });

      if ((cur > min && depois <= min) || depois == 0) {
        final alertRef = _alertCol.doc();
        tx.set(alertRef, {
          'produtoId': produtoId,
          'tipo': (depois == 0 ? 'sem_estoque' : 'baixo_estoque'),
          'quantidade': depois,
          'minimo': min,
          'createdAt': now,
        });
      }
    });
  }
}
