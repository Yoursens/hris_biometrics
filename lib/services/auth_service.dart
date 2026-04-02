// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import 'database_service.dart';

class AuthService {
  static AuthService? _instance;
  AuthService._();
  static AuthService get instance => _instance ??= AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  /// Register a new user with Email and Password
  Future<void> registerEmployee({
    required String email,
    required String password,
    required Employee employee,
  }) async {
    // 1. Create user in Firebase Auth
    UserCredential result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;
    if (user == null) throw 'Registration failed: User is null';

    // 2. Save detailed profile to Firestore
    final employeeData = employee.toMap();
    employeeData['uid'] = user.uid;
    employeeData['role'] = 'user'; // Default role
    await _firestore.collection('employees').doc(user.uid).set(employeeData);

    // 3. Create a registration activity log
    await _firestore.collection('activity_logs').add({
      'type': 'registration',
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'timestamp': FieldValue.serverTimestamp(),
      'details': 'New account created via mobile',
    });

    // 4. Save to Local SQLite
    await DatabaseService.instance.insertEmployee(employee);
  }

  /// Login with Email and Password
  Future<Employee?> login({
    required String email,
    required String password,
  }) async {
    // 1. Sign in with Firebase Auth
    UserCredential result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;
    if (user == null) return null;

    // 2. Fetch employee data
    DocumentSnapshot doc = await _firestore.collection('employees').doc(user.uid).get();
    
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final employee = Employee.fromMap(data);
      
      // 3. Log the login event
      await _firestore.collection('activity_logs').add({
        'type': 'login',
        'uid': user.uid,
        'employee_id': employee.employeeId,
        'employee_name': employee.fullName,
        'timestamp': FieldValue.serverTimestamp(),
        'device': 'Mobile App',
      });

      // 4. Sync/Update Local SQLite
      await DatabaseService.instance.insertEmployee(employee);
      
      return employee;
    }
    return null;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
