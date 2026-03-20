// lib/models/employee.dart
class Employee {
  final String id;
  final String employeeId;
  final String firstName;
  final String lastName;
  final String email;
  final String department;
  final String position;
  final String? phone;
  final String? photoPath;
  final String? faceEmbedding;
  final String? fingerprintHash;
  final String? pinHash;
  final String? pinSalt;
  final String? nfcTagId; // Added for NFC support
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Employee({
    required this.id,
    required this.employeeId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.department,
    required this.position,
    this.phone,
    this.photoPath,
    this.faceEmbedding,
    this.fingerprintHash,
    this.pinHash,
    this.pinSalt,
    this.nfcTagId,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName';
  String get initials => '${firstName[0]}${lastName[0]}'.toUpperCase();

  bool get hasFaceEnrolled => faceEmbedding != null;
  bool get hasFingerprintEnrolled => fingerprintHash != null;
  bool get hasPinSet => pinHash != null;
  bool get hasNfcEnrolled => nfcTagId != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'employee_id': employeeId,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'department': department,
        'position': position,
        'phone': phone,
        'photo_path': photoPath,
        'face_embedding': faceEmbedding,
        'fingerprint_hash': fingerprintHash,
        'pin_hash': pinHash,
        'pin_salt': pinSalt,
        'nfc_tag_id': nfcTagId,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Employee.fromMap(Map<String, dynamic> map) => Employee(
        id: map['id'],
        employeeId: map['employee_id'],
        firstName: map['first_name'],
        lastName: map['last_name'],
        email: map['email'],
        department: map['department'],
        position: map['position'],
        phone: map['phone'],
        photoPath: map['photo_path'],
        faceEmbedding: map['face_embedding'],
        fingerprintHash: map['fingerprint_hash'],
        pinHash: map['pin_hash'],
        pinSalt: map['pin_salt'],
        nfcTagId: map['nfc_tag_id'],
        isActive: (map['is_active'] as int) == 1,
        createdAt: DateTime.parse(map['created_at']),
        updatedAt: DateTime.parse(map['updated_at']),
      );

  Employee copyWith({
    String? photoPath,
    String? faceEmbedding,
    String? fingerprintHash,
    String? pinHash,
    String? pinSalt,
    String? nfcTagId,
    String? phone,
    String? department,
    String? position,
    bool? isActive,
  }) =>
      Employee(
        id: id,
        employeeId: employeeId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        department: department ?? this.department,
        position: position ?? this.position,
        phone: phone ?? this.phone,
        photoPath: photoPath ?? this.photoPath,
        faceEmbedding: faceEmbedding ?? this.faceEmbedding,
        fingerprintHash: fingerprintHash ?? this.fingerprintHash,
        pinHash: pinHash ?? this.pinHash,
        pinSalt: pinSalt ?? this.pinSalt,
        nfcTagId: nfcTagId ?? this.nfcTagId,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
