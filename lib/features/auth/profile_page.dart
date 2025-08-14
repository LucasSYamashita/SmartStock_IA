import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_input.dart';
import '../tenant/tenant_provider.dart';
import '../settings/theme_mode_provider.dart';

/// providers auxiliares --------------------------------------------------------

final _tenantDocProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .snapshots();
});

final _myMembershipProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (tenantId == null || uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid)
      .snapshots();
});

/// página ---------------------------------------------------------------------

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _name = TextEditingController();
  bool working = false;
  String? msg;

  User get user => FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _name.text = user.displayName ?? '';
  }

  Future<void> _saveName() async {
    final tenantId = ref.read(tenantIdProvider);
    setState(() {
      working = true;
      msg = null;
    });
    try {
      final name = _name.text.trim();
      await user.updateDisplayName(name);

      // Se houver tenant selecionado, salva também na membership da loja
      if (tenantId != null) {
        await FirebaseFirestore.instance
            .collection('tenants')
            .doc(tenantId)
            .collection('usuarios')
            .doc(user.uid)
            .set({
          'displayName': name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      setState(() => msg = 'Nome atualizado.');
    } catch (e) {
      setState(() => msg = e.toString());
    } finally {
      setState(() => working = false);
    }
  }

  Future<void> _sendResetPassword() async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Enviamos um e-mail para redefinir a senha.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _regenerateCode() async {
    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) return;
    try {
      final newCode = _randomCode();
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .update({'code': newCode});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Novo código: $newCode')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao regenerar código: $e')),
        );
      }
    }
  }

  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(
        6,
        (i) => chars[
            (DateTime.now().microsecondsSinceEpoch + i) % chars.length]).join();
  }

  void _showInviteSheet(String code, String tenantName) {
    final shareMsg = 'Olá! Para entrar na loja "$tenantName" no SmartStock:\n'
        '1) Crie seu login no app\n'
        '2) Vá em "Entrar em loja existente"\n'
        '3) Use o código: $code';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adicionar funcionário',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Compartilhe este código para o funcionário entrar na loja:'),
            const SizedBox(height: 8),
            Row(
              children: [
                SelectableText(code,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Copiar instruções'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareMsg));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Instruções copiadas')),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Dica: você pode regenerar o código quando quiser (somente admin).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantSnap = ref.watch(_tenantDocProvider);
    final membershipSnap = ref.watch(_myMembershipProvider);
    final themeMode = ref.watch(themeModeProvider);

    final isAdmin = membershipSnap.maybeWhen(
      data: (doc) => (doc?.data()?['role'] ?? '') == 'admin',
      orElse: () => false,
    );

    final tenantName = tenantSnap.maybeWhen(
      data: (doc) => (doc?.data()?['name'] ?? '(sem nome)').toString(),
      orElse: () => '—',
    );

    final tenantCode = tenantSnap.maybeWhen(
      data: (doc) => (doc?.data()?['code'] ?? '------').toString(),
      orElse: () => '------',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil & Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Conta
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                      radius: 28, child: Icon(Icons.person, size: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName ?? 'Sem nome',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(user.email ?? '-',
                            style: Theme.of(context).textTheme.bodyMedium),
                        if (!(user.emailVerified))
                          Text('E-mail não verificado',
                              style: TextStyle(color: Colors.orange.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Perfil: nome
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Perfil',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  AppTextField(controller: _name, label: 'Nome'),
                  const SizedBox(height: 8),
                  AppButton(
                      text: 'Salvar nome',
                      onPressed: working ? null : _saveName),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Senha
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Segurança',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  AppButton(
                    text: 'Enviar e-mail de redefinição de senha',
                    onPressed: _sendResetPassword,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Loja
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loja', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text('Nome: $tenantName')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text('Código: $tenantCode')),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: tenantCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código copiado')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Adicionar funcionário'),
                        onPressed: () =>
                            _showInviteSheet(tenantCode, tenantName),
                      ),
                      const SizedBox(width: 12),
                      if (isAdmin)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Regenerar código'),
                          onPressed: _regenerateCode,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Configurações do app
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.brightness_6),
                    title: const Text('Tema escuro'),
                    subtitle:
                        const Text('Alternar claro/escuro (ou seguir sistema)'),
                    trailing: DropdownButton<ThemeMode>(
                      value: themeMode,
                      onChanged: (m) => ref
                          .read(themeModeProvider.notifier)
                          .state = m ?? ThemeMode.system,
                      items: const [
                        DropdownMenuItem(
                            value: ThemeMode.system, child: Text('Sistema')),
                        DropdownMenuItem(
                            value: ThemeMode.light, child: Text('Claro')),
                        DropdownMenuItem(
                            value: ThemeMode.dark, child: Text('Escuro')),
                      ],
                    ),
                  ),
                  // espaço para futuras configs (idioma, moeda, etc.)
                ],
              ),
            ),
          ),

          if (msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(msg!, style: const TextStyle(color: Colors.blueGrey)),
            ),
        ],
      ),
    );
  }
}
