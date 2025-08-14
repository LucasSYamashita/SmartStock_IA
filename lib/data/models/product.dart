import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String nome;
  final String categoria;
  final String? sku;
  final double preco;
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

  factory Product.fromMap(String id, Map<String, dynamic> map) => Product(
    id: id,
    nome: map['nome'] as String,
    categoria: map['categoria'] as String? ?? '',
    sku: map['sku'] as String?,
    preco: (map['preco'] as num?)?.toDouble() ?? 0.0,
    quantidade: (map['quantidade'] as num?)?.toInt() ?? 0,
    estoqueMinimo: (map['estoqueMinimo'] as num?)?.toInt() ?? 0,
    ativo: map['ativo'] as bool? ?? true,
    createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );

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
}
