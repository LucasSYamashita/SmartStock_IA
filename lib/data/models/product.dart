import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String nome;
  final String categoria;
  final String? sku;
  final double preco; // preço de venda
  final int quantidade;
  final int estoqueMinimo;
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    required this.nome,
    required this.categoria,
    this.sku,
    required this.preco,
    required this.quantidade,
    required this.estoqueMinimo,
    required this.ativo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromMap(String id, Map<String, dynamic> map) {
    // compatibilidade com coleções antigas: 'valor'/'precoVenda'
    final precoAny = map['preco'] ?? map['valor'] ?? map['precoVenda'] ?? 0.0;
    final qtdAny = map['quantidade'] ?? map['Quantidade'] ?? 0;
    final minAny = map['estoqueMinimo'] ?? map['EstoqueMinimo'] ?? 0;
    final created = map['createdAt'];
    final updated = map['updatedAt'];

    return Product(
      id: id,
      nome: (map['nome'] ?? map['Nome'] ?? '').toString(),
      categoria: (map['categoria'] ?? '').toString(),
      sku: (map['sku'] as String?),
      preco: precoAny is num
          ? precoAny.toDouble()
          : double.tryParse('$precoAny') ?? 0.0,
      quantidade: qtdAny is num ? qtdAny.toInt() : int.tryParse('$qtdAny') ?? 0,
      estoqueMinimo:
          minAny is num ? minAny.toInt() : int.tryParse('$minAny') ?? 0,
      ativo: map['ativo'] as bool? ?? true,
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      updatedAt: updated is Timestamp ? updated.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'categoria': categoria,
        'sku': sku,
        'preco': preco,
        'quantidade': quantidade,
        'estoqueMinimo': estoqueMinimo,
        'ativo': ativo,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  Product copyWith({
    String? id,
    String? nome,
    String? categoria,
    String? sku,
    double? preco,
    int? quantidade,
    int? estoqueMinimo,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      sku: sku ?? this.sku,
      preco: preco ?? this.preco,
      quantidade: quantidade ?? this.quantidade,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
