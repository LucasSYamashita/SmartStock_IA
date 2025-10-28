import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_controller.dart';
import 'chat_service.dart';

// providers do app
import '../tenant/tenant_provider.dart';
import '../tenant/role_providers.dart';

final _chatServiceProvider = Provider<ChatService>((ref) => ChatService());

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  final tenantId = ref.watch(tenantIdProvider) ?? '';
  // role: admin > staff > viewer
  final isAdmin =
      tenantId.isNotEmpty ? ref.watch(isAdminProvider(tenantId)) : false;
  final isStaff =
      tenantId.isNotEmpty ? ref.watch(isStaffProvider(tenantId)) : false;
  final role = isAdmin ? 'admin' : (isStaff ? 'staff' : 'viewer');

  return ChatController(
    service: ref.read(_chatServiceProvider),
    tenantId: tenantId,
    role: role,
  );
});

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref.read(chatControllerProvider.notifier).send(txt);
      _input.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final tenantId = ref.watch(tenantIdProvider) ?? '';

    return Column(
      children: [
        if (tenantId.isEmpty)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Nenhuma loja ativa. Abra/entre em uma loja para usar o Chat.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.items.length,
            itemBuilder: (_, i) {
              final m = state.items[i];
              final mine = m.role == 'user';
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: mine
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    m.content,
                    style: TextStyle(
                      color: mine
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(
                    hintText: 'Digite aqui… ex.: entrada de 5 sabonetes a 10',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed:
                    (tenantId.isEmpty || _sending) ? null : () => _send(),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Enviar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
