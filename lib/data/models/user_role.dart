// lib/data/models/app_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? email;
  final String? displayName;

  /// 'admin' | 'staff' | 'viewer'
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.role = 'viewer',
    this.createdAt,
    this.updatedAt,
  });

  /// Constrói a partir de um Map (Firestore ou cache).
  /// Aceita Timestamp/DateTime/int(String epoch)/String ISO em createdAt/updatedAt.
  factory AppUser.fromMap(String uid, Map<String, dynamic>? map) {
    final m = map ?? const {};
    final normRole = _normalizeRole((m['role'] ?? 'viewer').toString());
    return AppUser(
      uid: uid,
      email: (m['email'] as String?)?.trim(),
      displayName: (m['displayName'] as String?)?.trim(),
      role: normRole,
      createdAt: _toDateTime(m['createdAt']),
      updatedAt: _toDateTime(m['updatedAt']),
    );
  }

  /// Conveniência para montar direto do FirebaseAuth.User
  /// (você pode injetar a role do membership depois).
  factory AppUser.fromFirebaseUser(
    dynamic user, {
    String role = 'viewer',
  }) {
    // `user` é tipicamente `firebase_auth.User`.
    return AppUser(
      uid: user.uid as String,
      email: user.email as String?,
      displayName: user.displayName as String?,
      role: _normalizeRole(role),
    );
  }

  AppUser copyWith({
    String? email,
    String? displayName,
    String? role,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role != null ? _normalizeRole(role) : this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Para salvar no Firestore. Converte DateTime -> Timestamp.
  Map<String, dynamic> toMap() {
    return {
      if (email != null) 'email': email,
      if (displayName != null) 'displayName': displayName,
      'role': role,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  // ----------------- helpers -----------------

  static String _normalizeRole(String raw) {
    final r = raw.toLowerCase().trim();
    if (r == 'admin' || r == 'staff') return r;
    return 'viewer';
  }

  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      // tenta ISO; se for epoch em string, tenta int
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
      final asInt = int.tryParse(v);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
    }
    return null;
  }
}
