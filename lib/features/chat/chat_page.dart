// lib/features/chat/chat_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_controller.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _useStreaming = false;
  bool _acting = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(chatControllerProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStock • Chat'),
        actions: [
          Row(
            children: [
              const Text('Streaming', style: TextStyle(color: Colors.white)),
              Switch(
                value: _useStreaming,
                onChanged: (v) => setState(() => _useStreaming = v),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _acting ? null : _actOnLastUserOrInput,
                icon: _acting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.playlist_add_check, color: Colors.white),
                label: const Text('Interpretar & Executar',
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: history.length,
              itemBuilder: (_, i) {
                final m = history[i];
                final isUser = m.role == 'user';
                final align =
                    isUser ? Alignment.centerRight : Alignment.centerLeft;
                final color = isUser
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(.6)
                    : Theme.of(context).colorScheme.surfaceVariant;

                return Align(
                  alignment: align,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SelectableText(m.content,
                          style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                );
              },
            ),
          ),
          _ComposerBar(controller: _input, onSend: _send),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty) return;
    _input.clear();

    final ctrl = ref.read(chatControllerProvider.notifier);
    if (_useStreaming) {
      await ctrl.sendStreaming(txt);
    } else {
      await ctrl.send(txt);
    }
  }

  Future<void> _actOnLastUserOrInput() async {
    final ctrl = ref.read(chatControllerProvider.notifier);
    final history = ref.read(chatControllerProvider);

    String? lastUser;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].role == 'user') {
        lastUser = history[i].content.trim();
        break;
      }
    }
    final fallback = _input.text.trim();
    final text = (lastUser?.isNotEmpty == true) ? lastUser! : fallback;

    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Digite uma mensagem antes.')),
        );
      }
      return;
    }

    setState(() => _acting = true);
    try {
      await ctrl.actFromText(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao executar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surface;
    final fill = cs.surfaceContainerHighest.withOpacity(0.8);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    Icon(Icons.chat_bubble_outline,
                        size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Digite sua mensagem…',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 44,
              width: 44,
              child: ElevatedButton(
                onPressed: onSend,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  elevation: 1,
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                child: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
