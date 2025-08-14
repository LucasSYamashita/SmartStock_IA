class AppUser {
  final String uid;
  final String email;
  final String? displayName;
  final String role; // 'admin' | 'staff' | 'viewer'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      email: (map['email'] ?? '').toString(),
      displayName: map['displayName'] as String?,
      role: (map['role'] ?? 'viewer').toString(),
      createdAt: null,
      updatedAt: null,
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'role': role,
      };
}
