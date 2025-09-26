// lib/data/models/movement.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Movement {
  final String id;
  final String produtoId;

  /// 'entrada' | 'saida'
  final String tipo;
  final int quantidade;
  final String motivo; // ex.: 'compra' | 'venda' | 'entrada manual'
  final String usuarioId;

  /// 'chatbot' | 'ui' | 'venda_manual' etc.
  final String origem;
  final String? mensagemOriginal;

  /// carimbado no servidor; pode vir como Timestamp/DateTime/etc
  final DateTime createdAt;

  const Movement({
    required this.id,
    required this.produtoId,
    required this.tipo,
    required this.quantidade,
    required this.motivo,
    required this.usuarioId,
    required this.origem,
    this.mensagemOriginal,
    required this.createdAt,
  });

  Movement copyWith({
    String? produtoId,
    String? tipo,
    int? quantidade,
    String? motivo,
    String? usuarioId,
    String? origem,
    String? mensagemOriginal,
    DateTime? createdAt,
  }) {
    return Movement(
      id: id,
      produtoId: produtoId ?? this.produtoId,
      tipo: tipo ?? this.tipo,
      quantidade: quantidade ?? this.quantidade,
      motivo: motivo ?? this.motivo,
      usuarioId: usuarioId ?? this.usuarioId,
      origem: origem ?? this.origem,
      mensagemOriginal: mensagemOriginal ?? this.mensagemOriginal,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Parsing seguro de tipos variados que podem vir do Firestore.
  static DateTime _toDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
      final epoch = int.tryParse(v);
      if (epoch != null) {
        return DateTime.fromMillisecondsSinceEpoch(epoch);
      }
    }
    return DateTime.now();
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  factory Movement.fromMap(String id, Map<String, dynamic> map) {
    return Movement(
      id: id,
      produtoId: (map['produtoId'] ?? '').toString(),
      tipo: (map['tipo'] ?? '').toString(), // 'entrada' | 'saida'
      quantidade: _toInt(map['quantidade']),
      motivo: (map['motivo'] ?? '').toString(),
      usuarioId: (map['usuarioId'] ?? '').toString(),
      origem: (map['origem'] ?? 'ui').toString(),
      mensagemOriginal: (map['mensagemOriginal'] as String?)?.trim(),
      createdAt: _toDate(map['createdAt']),
    );
  }

  factory Movement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Movement.fromMap(doc.id, doc.data() ?? const {});
  }

  /// Quando criar um movimento novo, deixe `createdAt` nulo no Map para o servidor preencher.
  Map<String, dynamic> toMap({bool serverStampOnCreate = true}) {
    return {
      'produtoId': produtoId,
      'tipo': tipo,
      'quantidade': quantidade,
      'motivo': motivo,
      'usuarioId': usuarioId,
      'origem': origem,
      'mensagemOriginal': mensagemOriginal,
      'createdAt': serverStampOnCreate
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt),
    };
  }
}
