// lib/models/employee.dart

// Sentinel class to distinguish between "not provided" and explicit null
class _Unset {
  const _Unset();
}

const _unset = _Unset();

class Employee {
  final String id;
  final String employeeId;
  final String firstName;
  final String lastName;
  final String email;
  final String department;
  final String position; // We'll use this to identify "Driver"
  final String? phone;
  final String? photoPath;
  final String? faceEmbedding;
  final String? fingerprintHash;
  final String? pinHash;
  final String? pinSalt;
  final String? nfcTagId;
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

  // Helper to identify if user is a driver
  bool get isDriver => position.toLowerCase() == 'driver';

  // Computed getters — driven by actual data fields
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
    Object? phone = _unset,
    Object? photoPath = _unset,
    Object? faceEmbedding = _unset,
    Object? fingerprintHash = _unset,
    Object? pinHash = _unset,
    Object? pinSalt = _unset,
    Object? nfcTagId = _unset,
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
        phone: phone is _Unset ? this.phone : phone as String?,
        photoPath: photoPath is _Unset ? this.photoPath : photoPath as String?,
        faceEmbedding:
        faceEmbedding is _Unset ? this.faceEmbedding : faceEmbedding as String?,
        fingerprintHash:
        fingerprintHash is _Unset ? this.fingerprintHash : fingerprintHash as String?,
        pinHash: pinHash is _Unset ? this.pinHash : pinHash as String?,
        pinSalt: pinSalt is _Unset ? this.pinSalt : pinSalt as String?,
        nfcTagId: nfcTagId is _Unset ? this.nfcTagId : nfcTagId as String?,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
