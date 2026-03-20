// lib/services/api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'security_service.dart';

class ApiService {
  static ApiService? _instance;
  late final Dio _dio;
  
  // Server config - update to your backend URL
  static const String _baseUrl = 'https://api.hrisbiometrics.company.com/v1';
  static const int _timeout = 30;

  ApiService._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: _timeout),
      receiveTimeout: const Duration(seconds: _timeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-App-Version': '1.0.0',
      },
    ));
    _setupInterceptors();
  }

  static ApiService get instance => _instance ??= ApiService._();

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Attach session token
        final session = await SecurityService.instance.getCurrentEmployeeId();
        if (session != null) {
          options.headers['X-Employee-ID'] = session;
        }
        // Attach device ID
        final deviceId = await SecurityService.instance.getDeviceId();
        options.headers['X-Device-ID'] = deviceId;
        handler.next(options);
      },
      onResponse: (response, handler) {
        handler.next(response);
      },
      onError: (error, handler) {
        handler.next(error);
      },
    ));

    // Logging interceptor (dev only)
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
    ));
  }

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // ============ AUTHENTICATION ============
  Future<ApiResponse> login(String employeeId, String password) async {
    return _safeCall(() => _dio.post('/auth/login', data: {
          'employee_id': employeeId,
          'password': password,
        }));
  }

  Future<ApiResponse> refreshToken(String refreshToken) async {
    return _safeCall(() => _dio.post('/auth/refresh', data: {
          'refresh_token': refreshToken,
        }));
  }

  Future<ApiResponse> logout() async {
    return _safeCall(() => _dio.post('/auth/logout'));
  }

  // ============ ATTENDANCE SYNC ============
  Future<ApiResponse> syncAttendance(List<Map<String, dynamic>> records) async {
    return _safeCall(() => _dio.post('/attendance/sync', data: {
          'records': records,
          'synced_at': DateTime.now().toIso8601String(),
        }));
  }

  Future<ApiResponse> getAttendanceSummary(
      String employeeId, String month) async {
    return _safeCall(() => _dio.get('/attendance/summary', queryParameters: {
          'employee_id': employeeId,
          'month': month,
        }));
  }

  Future<ApiResponse> clockIn(Map<String, dynamic> data) async {
    return _safeCall(() => _dio.post('/attendance/clock-in', data: data));
  }

  Future<ApiResponse> clockOut(Map<String, dynamic> data) async {
    return _safeCall(() => _dio.post('/attendance/clock-out', data: data));
  }

  // ============ EMPLOYEE ============
  Future<ApiResponse> syncEmployee(Map<String, dynamic> employee) async {
    return _safeCall(() => _dio.put('/employees/${employee['id']}',
        data: employee));
  }

  Future<ApiResponse> getEmployees({int page = 1, int limit = 20}) async {
    return _safeCall(() => _dio.get('/employees',
        queryParameters: {'page': page, 'limit': limit}));
  }

  Future<ApiResponse> getEmployeeProfile(String id) async {
    return _safeCall(() => _dio.get('/employees/$id'));
  }

  // ============ LEAVE ============
  Future<ApiResponse> submitLeave(Map<String, dynamic> data) async {
    return _safeCall(() => _dio.post('/leaves', data: data));
  }

  Future<ApiResponse> getLeaves(String employeeId) async {
    return _safeCall(() => _dio.get('/leaves',
        queryParameters: {'employee_id': employeeId}));
  }

  Future<ApiResponse> approveLeave(String leaveId, bool approve) async {
    return _safeCall(() => _dio.put('/leaves/$leaveId', data: {
          'status': approve ? 'approved' : 'rejected',
        }));
  }

  // ============ REPORTS ============
  Future<ApiResponse> getDashboardStats() async {
    return _safeCall(() => _dio.get('/reports/dashboard'));
  }

  Future<ApiResponse> exportAttendanceReport(
      String from, String to, String format) async {
    return _safeCall(() => _dio.post('/reports/export', data: {
          'from': from,
          'to': to,
          'format': format,
        }));
  }

  // ============ NOTIFICATIONS ============
  Future<ApiResponse> getNotifications() async {
    return _safeCall(() => _dio.get('/notifications'));
  }

  Future<ApiResponse> markNotificationRead(String id) async {
    return _safeCall(() => _dio.put('/notifications/$id/read'));
  }

  // ============ BIOMETRIC ENROLLMENT ============
  Future<ApiResponse> enrollFace(String employeeId, String encryptedData) async {
    return _safeCall(() => _dio.post('/biometrics/face/enroll', data: {
          'employee_id': employeeId,
          'face_data': encryptedData,
          'enrolled_at': DateTime.now().toIso8601String(),
        }));
  }

  Future<ApiResponse> verifyFace(
      String employeeId, String encryptedData) async {
    return _safeCall(() => _dio.post('/biometrics/face/verify', data: {
          'employee_id': employeeId,
          'face_data': encryptedData,
        }));
  }

  // ============ HELPER ============
  Future<ApiResponse> _safeCall(Future<Response> Function() call) async {
    try {
      final online = await isOnline();
      if (!online) {
        return ApiResponse(
            success: false,
            message: 'No internet connection. Changes saved locally.',
            isOffline: true);
      }
      final response = await call();
      return ApiResponse(
        success: response.statusCode == 200 || response.statusCode == 201,
        data: response.data,
        statusCode: response.statusCode,
        message: response.data?['message'] ?? 'Success',
      );
    } on DioException catch (e) {
      return ApiResponse(
        success: false,
        message: _parseError(e),
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResponse(success: false, message: 'Unexpected error: $e');
    }
  }

  String _parseError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please try again.';
      case DioExceptionType.badResponse:
        final msg = e.response?.data?['message'];
        return msg ?? 'Server error (${e.response?.statusCode})';
      case DioExceptionType.connectionError:
        return 'Cannot connect to server.';
      default:
        return 'Network error occurred.';
    }
  }
}

class ApiResponse {
  final bool success;
  final dynamic data;
  final String? message;
  final int? statusCode;
  final bool isOffline;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
    this.isOffline = false,
  });
}
