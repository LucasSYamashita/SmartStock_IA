import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tenant_provider.dart';
import 'tenant_join_create_page.dart';

class TenantGate extends ConsumerStatefulWidget {
  const TenantGate({super.key});
  @override
  ConsumerState<TenantGate> createState() => _TenantGateState();
}

class _TenantGateState extends ConsumerState<TenantGate> {
  late final Future<_Result> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Result> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final q = await FirebaseFirestore.instance
          .collectionGroup('usuarios')
          .where('uid', isEqualTo: uid)
          .get();

      if (q.docs.isEmpty) return _Result.none();
      if (q.docs.length == 1) {
        final tenantId = q.docs.first.reference.parent.parent!.id;
        return _Result.single(tenantId);
      }
      final items = q.docs.map((d) => d.reference.parent.parent!).toList();
      return _Result.multi(items);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return _Result.none();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Result>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return const TenantJoinCreatePage();
        }
        final res = snap.data!;
        if (res.kind == _Kind.none) return const TenantJoinCreatePage();

        if (res.kind == _Kind.single) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await ref.read(tenantIdProvider.notifier).set(res.tenantId!);
          });
          return const SizedBox.shrink();
        }

        final items = res.items!;
        return Scaffold(
          appBar: AppBar(title: const Text('Escolha a loja')),
          body: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) =>
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: items[i].get(),
              builder: (_, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const ListTile(title: Text('Carregando...'));
                }
                final name =
                    (s.data?.data()?['name'] ?? items[i].id).toString();
                return ListTile(
                  title: Text(name),
                  onTap: () async {
                    await ref.read(tenantIdProvider.notifier).set(items[i].id);
                    if (context.mounted) {
                      Navigator.of(context).pushReplacementNamed('/');
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

enum _Kind { none, single, multi }

class _Result {
  final _Kind kind;
  final String? tenantId;
  final List<DocumentReference<Map<String, dynamic>>>? items;
  _Result._(this.kind, this.tenantId, this.items);
  factory _Result.none() => _Result._(_Kind.none, null, null);
  factory _Result.single(String id) => _Result._(_Kind.single, id, null);
  factory _Result.multi(List<DocumentReference<Map<String, dynamic>>> items) =>
      _Result._(_Kind.multi, null, items);
}
