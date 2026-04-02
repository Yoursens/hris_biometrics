// lib/screens/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math' show cos, sqrt, asin;
import '../theme/app_theme.dart';
import 'package:rxdart/rxdart.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _tabIndex = 0;

  // Office Location (Must match GeofenceService)
  static const double _officeLat = 14.6114;
  static const double _officeLng = 120.9936;
  static const double _radiusLimit = 1500.0; // 1.5km

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('Admin Master Dashboard'),
        backgroundColor: AppColors.primary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _tabItem(0, 'Registrations', Icons.person_add_rounded),
                _tabItem(1, 'Logins', Icons.vpn_key_rounded),
                _tabItem(2, 'User Activity Tables', Icons.view_list_rounded),
                _tabItem(3, 'Live Tracking', Icons.my_location_rounded),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientDark),
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _buildFilteredActivityTable('registration'),
            _buildFilteredActivityTable('login'),
            _buildPerUserActivityTables(),
            _buildLiveTrackingTable(),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(int index, String label, IconData icon) {
    bool active = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 3))
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: active ? AppColors.accent : AppColors.textMuted, fontWeight: active ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // --- 1 & 2: Table for Registrations and Logins ---
  Widget _buildFilteredActivityTable(String filterType) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('activity_logs')
          .where('type', isEqualTo: filterType)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        
        return _buildTableContainer(
          title: filterType.toUpperCase(),
          columns: ['Employee ID', 'Name', 'Timestamp', 'Device'],
          rows: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = (data['timestamp'] as Timestamp?)?.toDate();
            return [
              data['employee_id'] ?? 'N/A',
              data['employee_name'] ?? 'Unknown',
              ts != null ? DateFormat('MMM dd, hh:mm a').format(ts) : '---',
              data['device'] ?? 'Mobile',
            ];
          }).toList(),
        );
      },
    );
  }

  // --- 3: Separate Tables for Each User (Time In, Stay Duration, Clock Out) ---
  Widget _buildPerUserActivityTables() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('employees').snapshots(),
      builder: (context, empSnapshot) {
        if (!empSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final employees = empSnapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: employees.length,
          itemBuilder: (context, index) {
            final empData = employees[index].data() as Map<String, dynamic>;
            final empId = empData['employee_id'];
            final empName = "${empData['first_name']} ${empData['last_name']}";

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(empName, style: const TextStyle(color: AppColors.accent, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _getCombinedUserLogs(empId),
                  builder: (context, logSnapshot) {
                    if (!logSnapshot.hasData) return const SizedBox(height: 50, child: Center(child: LinearProgressIndicator()));
                    final logs = logSnapshot.data!;

                    return _buildTableContainer(
                      title: "Activity for $empId",
                      columns: ['Time In', 'Time Out', 'Stay Duration', 'Date'],
                      rows: logs.map((log) => [
                        log['time_in'] ?? '---',
                        log['time_out'] ?? 'Still In',
                        _calculateStayDuration(log['time_in'], log['time_out'], log['date']),
                        log['date'] ?? '---',
                      ]).toList(),
                    );
                  },
                ),
                const SizedBox(height: 32),
                const Divider(color: Colors.white24),
              ],
            );
          },
        );
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _getCombinedUserLogs(String empId) {
    final ins = FirebaseFirestore.instance
        .collection('clock_ins')
        .where('employee_id', isEqualTo: empId)
        .snapshots();
    final outs = FirebaseFirestore.instance
        .collection('clock_outs')
        .where('employee_id', isEqualTo: empId)
        .snapshots();

    return CombineLatestStream.list([ins, outs]).map((snapshots) {
      final List<Map<String, dynamic>> combined = [];
      final inDocs = snapshots[0].docs;
      final outDocs = snapshots[1].docs;

      for (var inDoc in inDocs) {
        final inData = inDoc.data() as Map<String, dynamic>;
        final attendanceId = inData['attendance_id'];
        
        // Find matching clock out
        var outData = outDocs.where((d) => (d.data() as Map)['attendance_id'] == attendanceId).firstOrNull?.data() as Map<String, dynamic>?;

        combined.add({
          'time_in': inData['time_in'],
          'time_out': outData?['time_out'],
          'date': inData['date'],
          'saved_at': inData['saved_at'],
        });
      }
      
      combined.sort((a, b) => (b['saved_at'] ?? "").compareTo(a['saved_at'] ?? ""));
      return combined;
    });
  }

  String _calculateStayDuration(String? timeIn, String? timeOut, String? date) {
    if (timeIn == null || date == null) return '---';
    try {
      final start = DateTime.parse("$date $timeIn");
      final end = timeOut != null ? DateTime.parse("$date $timeOut") : DateTime.now();
      
      final diff = end.difference(start);
      if (diff.isNegative) return "0h 0m";
      
      return "${diff.inHours}h ${diff.inMinutes % 60}m";
    } catch (e) {
      return '---';
    }
  }

  // --- 4: Table for Live Tracking with Perimeter ---
  Widget _buildLiveTrackingTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('user_locations').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;

        return _buildTableContainer(
          title: "LIVE TRACKING",
          columns: ['Employee ID', 'Location', 'Distance', 'Perimeter', 'Last Sync'],
          rows: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            double lat = data['latitude'] ?? 0.0;
            double lng = data['longitude'] ?? 0.0;
            double distance = _calculateDistance(lat, lng, _officeLat, _officeLng) * 1000;
            bool isInside = distance <= _radiusLimit;
            final lastUpdate = (data['last_updated'] as Timestamp?)?.toDate();

            return [
              data['employee_id'] ?? 'N/A',
              '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
              '${distance.toStringAsFixed(0)}m',
              isInside ? 'INSIDE' : 'OUTSIDE',
              lastUpdate != null ? DateFormat('hh:mm:ss a').format(lastUpdate) : '---',
            ];
          }).toList(),
        );
      },
    );
  }

  // --- Reusable Table Component ---
  Widget _buildTableContainer({required String title, required List<String> columns, required List<List<dynamic>> rows}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              columns: columns.map((c) => DataColumn(label: Text(c, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12)))).toList(),
              rows: rows.map((row) => DataRow(
                cells: row.map((cell) {
                  bool isOutside = cell == 'OUTSIDE';
                  bool isStillIn = cell == 'Still In';
                  return DataCell(Text(
                    cell.toString(),
                    style: TextStyle(
                      color: isOutside ? Colors.redAccent : (isStillIn ? AppColors.warning : Colors.white),
                      fontSize: 11,
                      fontWeight: isOutside ? FontWeight.bold : FontWeight.normal,
                    ),
                  ));
                }).toList()
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
}
