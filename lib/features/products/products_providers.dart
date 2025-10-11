// lib/features/products/products_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/product.dart';
import '../tenant/tenant_provider.dart';

final productsStreamProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('produtos')
      .orderBy('nomeLower') // ou 'nome' se tiver docs antigos sem nomeLower
      .snapshots()
      .map((qs) =>
          qs.docs.map((d) => Product.fromFirestore(d.id, d.data())).toList());
});
