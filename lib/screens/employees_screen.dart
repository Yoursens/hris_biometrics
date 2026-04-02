import 'package:flutter/material.dart';

// ─── THE WIDGET (MainScreen is looking for this) ───────────────────────────
class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Employees', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Center(
        child: Text(
          'Employee List Screen',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
    );
  }
}

// ─── THE DATA MODEL (Keep this below the widget) ───────────────────────────
class Employee {
  final String id;
  final String employeeId;
  final String fullName;
  final String position;
  final String department;
  final String? email;
  final String? phone;
  final bool hasFaceEnrolled;
  final bool hasFingerprintEnrolled;
  final bool hasPinSet;

  Employee({
    required this.id,
    required this.employeeId,
    required this.fullName,
    required this.position,
    required this.department,
    this.email,
    this.phone,
    this.hasFaceEnrolled = false,
    this.hasFingerprintEnrolled = false,
    this.hasPinSet = false,
  });

  String get initials {
    final parts = fullName.trim().split(' ').where((e) => e.isNotEmpty).toList();

    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    } else {
      return 'EM';
    }
  }

  Employee copyWith({
    String? id,
    String? employeeId,
    String? fullName,
    String? position,
    String? department,
    String? email,
    String? phone,
    bool? hasFaceEnrolled,
    bool? hasFingerprintEnrolled,
    bool? hasPinSet,
  }) {
    return Employee(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      fullName: fullName ?? this.fullName,
      position: position ?? this.position,
      department: department ?? this.department,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      hasFaceEnrolled: hasFaceEnrolled ?? this.hasFaceEnrolled,
      hasFingerprintEnrolled:
      hasFingerprintEnrolled ?? this.hasFingerprintEnrolled,
      hasPinSet: hasPinSet ?? this.hasPinSet,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'fullName': fullName,
      'position': position,
      'department': department,
      'email': email,
      'phone': phone,
      'hasFaceEnrolled': hasFaceEnrolled,
      'hasFingerprintEnrolled': hasFingerprintEnrolled,
      'hasPinSet': hasPinSet,
    };
  }

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id']?.toString() ?? '',
      employeeId: map['employeeId']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      position: map['position']?.toString() ?? '',
      department: map['department']?.toString() ?? '',
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      hasFaceEnrolled: _toBool(map['hasFaceEnrolled']),
      hasFingerprintEnrolled: _toBool(map['hasFingerprintEnrolled']),
      hasPinSet: _toBool(map['hasPinSet']),
    );
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
    return false;
  }
}