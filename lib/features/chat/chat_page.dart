import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tenant/tenant_provider.dart';
import '../tenant/role_providers.dart';
import 'chat_controller.dart';

class ChatPage extends ConsumerWidget {
  final String tenantId;
  final String role;
  const ChatPage({super.key, required this.tenantId, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(
        chatControllerProvider((tenantId: tenantId, role: role)).notifier);
    final messages =
        ref.watch(chatControllerProvider((tenantId: tenantId, role: role)));

    final txt = TextEditingController();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tenant: $tenantId · Role: $role',
                  style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i];
                final isUser = m.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF424242),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(m.content,
                        style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: txt,
                    decoration: const InputDecoration(
                      hintText:
                          'ex.: entrada coca-cola • depois: 10 unidades • depois: a 10 ou "pular"',
                      filled: true,
                    ),
                    onSubmitted: (_) async {
                      final t = txt.text.trim();
                      if (t.isEmpty) return;
                      await ctrl.send(t);
                      txt.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final t = txt.text.trim();
                    if (t.isEmpty) return;
                    await ctrl.send(t);
                    txt.clear();
                  },
                  child: const Text('Enviar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
