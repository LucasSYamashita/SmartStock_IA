import 'package:cloud_firestore/cloud_firestore.dart';

/// Encerrar conexões e limpar cache/IndexedDB (WEB).
/// Use ao trocar de tenant/loja OU se cair no erro INTERNAL ASSERTION.
class FirestoreReset {
  static bool _resetting = false;

  static Future<void> repair() async {
    if (_resetting) return;
    _resetting = true;
    try {
      // 1) Encerra todas as conexões/listeners internos
      await FirebaseFirestore.instance.terminate();

      // 2) Limpa a persistência (IndexedDB). Só funciona com persistence habilitado.
      await FirebaseFirestore.instance.clearPersistence();

      // 3) Recria a instância “a quente”
      // No FlutterFire, após terminate/clearPersistence, o próximo acesso “reabre”.
      // Opcional: reconfigurar persistence
      await FirebaseFirestore.instance
          .enablePersistence(const PersistenceSettings(synchronizeTabs: true));

      // Opcional: reforçar configurações
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } finally {
      _resetting = false;
    }
  }
}
