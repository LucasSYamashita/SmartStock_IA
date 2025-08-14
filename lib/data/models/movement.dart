import 'package:cloud_firestore/cloud_firestore.dart';

class Movement {
  final String id;
  final String produtoId;
  final String tipo; // 'entrada' | 'saida'
  final int quantidade;
  final String motivo; // 'compra' | 'venda' | ...
  final String usuarioId;
  final String origem; // 'chatbot' | 'ui'
  final String? mensagemOriginal;
  final DateTime createdAt;

  Movement({
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

  factory Movement.fromMap(String id, Map<String, dynamic> map) => Movement(
    id: id,
    produtoId: map['produtoId'] as String,
    tipo: map['tipo'] as String,
    quantidade: (map['quantidade'] as num?)?.toInt() ?? 0,
    motivo: map['motivo'] as String? ?? '',
    usuarioId: map['usuarioId'] as String? ?? '',
    origem: map['origem'] as String? ?? 'ui',
    mensagemOriginal: map['mensagemOriginal'] as String?,
    createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'produtoId': produtoId,
    'tipo': tipo,
    'quantidade': quantidade,
    'motivo': motivo,
    'usuarioId': usuarioId,
    'origem': origem,
    'mensagemOriginal': mensagemOriginal,
    'createdAt': createdAt,
  };
}
