import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';

class TeamManagementPage extends ConsumerWidget {
  const TeamManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(body: Center(child: Text('Selecione uma loja.')));
    }

    final col = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('usuarios')
        .orderBy('displayName');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipe'),
        actions: [
          IconButton(
            tooltip: 'Gerar convite',
            onPressed: () => _showInviteSheet(context, tenantId),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Sem membros.'));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();
              final displayName = (m['displayName'] ?? '-').toString();
              final email = (m['email'] ?? '').toString();
              final role = (m['role'] ?? 'staff').toString();
              final active = (m['active'] ?? true) == true;

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                      child: Text(displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?')),
                  title: Text(displayName),
                  subtitle: Text(email.isEmpty ? d.id : email),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'toggle') {
                        await d.reference.update({
                          'active': !active,
                          'updatedAt': FieldValue.serverTimestamp()
                        });
                      }
                      if (v == 'admin' || v == 'staff') {
                        await d.reference.update({
                          'role': v,
                          'updatedAt': FieldValue.serverTimestamp()
                        });
                      }
                      if (v == 'delete') {
                        await _removeMember(context, ref, d.id, role);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'toggle',
                        child: ListTile(
                          leading: Icon(
                              active ? Icons.visibility_off : Icons.visibility),
                          title: Text(active ? 'Desativar' : 'Ativar'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: role == 'admin' ? 'staff' : 'admin',
                        child: ListTile(
                          leading: const Icon(Icons.swap_horiz),
                          title: Text(role == 'admin'
                              ? 'Tornar STAFF'
                              : 'Tornar ADMIN'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Remover da loja'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    String uidToRemove,
    String roleOfUser,
  ) async {
    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) return;
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    // Não permitir remover a si mesmo
    if (uidToRemove == myUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você não pode remover a si mesmo.')),
      );
      return;
    }

    // Se for admin, checa se ele é o último admin
    if (roleOfUser == 'admin') {
      final admins = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .collection('usuarios')
          .where('role', isEqualTo: 'admin')
          .get();
      if (admins.docs.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não é possível remover o último ADMIN da loja.')),
        );
        return;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover usuário'),
        content: const Text('Deseja remover este usuário da loja?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;

    await FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('usuarios')
        .doc(uidToRemove)
        .delete();

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Usuário removido.')));
    }
  }

  void _showInviteSheet(BuildContext context, String tenantId) {
    final code = _genCode();
    String role = 'staff';
    bool singleUse = true;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gerar convite',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Papel: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(value: 'staff', child: Text('Staff')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (v) => setState(() => role = v ?? 'staff'),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Text('Uso único'),
                      Switch(
                          value: singleUse,
                          onChanged: (v) => setState(() => singleUse = v)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText('Código: $code',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código copiado')));
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Salvar convite'),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('tenant_invites')
                          .doc(code)
                          .set({
                        'tenantId': tenantId,
                        'role': role,
                        'singleUse': singleUse,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) Navigator.pop(context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Convite salvo ($role): $code')));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Quem usar este código vai entrar diretamente na loja com o papel selecionado.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _genCode({int len = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
