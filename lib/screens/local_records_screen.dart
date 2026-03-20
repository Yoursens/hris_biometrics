// lib/screens/local_records_screen.dart
//
// In-app viewer for all locally saved attendance JSON files.
// Accessible from the profile or reports screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';

class LocalRecordsScreen extends StatefulWidget {
  const LocalRecordsScreen({super.key});

  @override
  State<LocalRecordsScreen> createState() => _LocalRecordsScreenState();
}

class _LocalRecordsScreenState extends State<LocalRecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> _dates = [];
  String _selectedDate = '';
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  bool _loadingRecords = false;
  String _storageSize = '...';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDates() async {
    setState(() => _loading = true);
    final dates = await DatabaseService.instance.getLocalAttendanceDates();
    final size = await DatabaseService.instance.getLocalStorageSize();
    setState(() {
      _dates = dates;
      _storageSize = size;
      _loading = false;
      if (dates.isNotEmpty) {
        _selectedDate = dates.first;
        _loadRecords(dates.first);
      }
    });
  }

  Future<void> _loadRecords(String date) async {
    setState(() { _loadingRecords = true; _selectedDate = date; });
    final records = await DatabaseService.instance.getLocalRecordsForDate(date);
    // Sort: summaries last, clock_in first
    records.sort((a, b) {
      final order = {'clock_in': 0, 'clock_out': 1};
      return (order[a['event']] ?? 9).compareTo(order[b['event']] ?? 9);
    });
    setState(() { _records = records; _loadingRecords = false; });
  }

  Future<void> _syncNow() async {
    if (!ConnectivityService.instance.isOnline) {
      _showSnack('No internet connection', AppColors.warning);
      return;
    }
    _showSnack('Syncing to database...', AppColors.accent);
    final result = await DatabaseService.instance.syncLocalFilesToDatabase();
    await SyncService.instance.syncPending();
    _showSnack(
      result.hasChanges
          ? '✓ ${result.inserted} record(s) synced to database'
          : 'All records already in database',
      result.hasChanges ? AppColors.success : AppColors.textSecondary,
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Local Records',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        actions: [
          // Sync now button
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: AppColors.accent),
            tooltip: 'Sync to database',
            onPressed: _syncNow,
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: _loadDates,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Records'),
            Tab(text: 'Storage Info'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildRecordsTab(),
          _buildStorageTab(),
        ],
      ),
    );
  }

  // ── Records Tab ───────────────────────────────────────────────────────────

  Widget _buildRecordsTab() {
    if (_dates.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open_rounded,
              color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          const Text('No records saved yet',
              style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          const Text('Clock in to create your first record',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ]),
      );
    }

    return Row(children: [
      // Date list sidebar
      Container(
        width: 110,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.cardBorder)),
        ),
        child: ListView.builder(
          itemCount: _dates.length,
          itemBuilder: (_, i) {
            final date = _dates[i];
            final selected = date == _selectedDate;
            return GestureDetector(
              onTap: () => _loadRecords(date),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Column(children: [
                  Text(
                    _shortMonth(date),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.accent : AppColors.textMuted),
                  ),
                  Text(
                    _dayNum(date),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.accent : AppColors.textPrimary),
                  ),
                  Text(
                    _year(date),
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textMuted),
                  ),
                ]),
              ),
            );
          },
        ),
      ),

      // Records for selected date
      Expanded(
        child: _loadingRecords
            ? const Center(
            child: CircularProgressIndicator(color: AppColors.accent))
            : _records.isEmpty
            ? const Center(
            child: Text('No records for this date',
                style: TextStyle(color: AppColors.textMuted)))
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _records.length,
          itemBuilder: (_, i) => _buildRecordCard(_records[i]),
        ),
      ),
    ]);
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final event = record['event'] as String? ?? '';
    final isClockIn = event == 'clock_in';
    final isSummary = record['_file']?.toString().contains('summary') ?? false;

    if (isSummary) return _buildSummaryCard(record);

    final color = isClockIn ? AppColors.success : AppColors.accentSecondary;
    final icon = isClockIn ? Icons.login_rounded : Icons.logout_rounded;
    final method = record['auth_method'] as String? ?? '';
    final time = isClockIn
        ? record['time_in'] as String? ?? '--'
        : record['time_out'] as String? ?? '--';
    final isLate = record['is_late'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(
                  isClockIn ? 'Clock In' : 'Clock Out',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: color),
                ),
                if (isLate) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('LATE',
                        style: TextStyle(fontSize: 9, color: AppColors.warning,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              Text(time,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ]),
          ),
          // Auth method badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_methodIcon(method), size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(_methodLabel(method),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> record) {
    final timeIn = record['time_in'] as String? ?? '--';
    final timeOut = record['time_out'] as String? ?? '--';
    final duration = record['work_duration'] as String? ?? '--';
    final status = record['status'] as String? ?? 'present';

    final statusColor = status == 'late' ? AppColors.warning : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.summarize_rounded,
              color: AppColors.accent, size: 16),
          const SizedBox(width: 6),
          const Text('Daily Summary',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(status.toUpperCase(),
                style: TextStyle(fontSize: 9, color: statusColor,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _summaryItem('Time In', timeIn, AppColors.success),
          const SizedBox(width: 12),
          _summaryItem('Time Out', timeOut, AppColors.accentSecondary),
          const SizedBox(width: 12),
          _summaryItem('Duration', duration, AppColors.accent),
        ]),
      ]),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }

  // ── Storage Tab ───────────────────────────────────────────────────────────

  Widget _buildStorageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Storage location card
        _infoCard(
          icon: Icons.folder_rounded,
          iconColor: AppColors.accent,
          title: 'Storage Location',
          subtitle: 'Saved to Downloads/HRIS_Biometrics/\nVisible in your phone\'s file manager',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('ACCESSIBLE',
                style: TextStyle(fontSize: 9, color: AppColors.success,
                    fontWeight: FontWeight.w800)),
          ),
        ),

        const SizedBox(height: 12),

        // Size card
        _infoCard(
          icon: Icons.storage_rounded,
          iconColor: AppColors.accentSecondary,
          title: 'Total Size',
          subtitle: _storageSize,
        ),

        const SizedBox(height: 12),

        // Total records
        _infoCard(
          icon: Icons.calendar_month_rounded,
          iconColor: AppColors.warning,
          title: 'Days with Records',
          subtitle: '${_dates.length} day(s) saved',
        ),

        const SizedBox(height: 24),
        const Text('Folder Structure',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),

        // Folder tree
        _folderTree(),

        const SizedBox(height: 24),

        // Sync button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _syncNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Sync All Records to Database',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),

        const SizedBox(height: 12),

        // Connectivity status
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ConnectivityService.instance.isOnline
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ConnectivityService.instance.isOnline
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(children: [
            Icon(
              ConnectivityService.instance.isOnline
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded,
              color: ConnectivityService.instance.isOnline
                  ? AppColors.success
                  : AppColors.warning,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              ConnectivityService.instance.isOnline
                  ? 'Online — records sync automatically'
                  : 'Offline — records saved to device, will sync when online',
              style: TextStyle(
                  fontSize: 11,
                  color: ConnectivityService.instance.isOnline
                      ? AppColors.success
                      : AppColors.warning),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted,
                    height: 1.4)),
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _folderTree() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _treeItem('📁 HRIS_Biometrics/', 0, AppColors.accent),
        _treeItem('📁 attendance/', 1, AppColors.success),
        _treeItem('📁 2026-03-02/', 2, AppColors.textSecondary),
        _treeItem('📄 EMP-001_clock_in_09-00.json', 3, AppColors.textMuted),
        _treeItem('📄 EMP-001_clock_out_18-00.json', 3, AppColors.textMuted),
        _treeItem('📄 EMP-001_summary.json', 3, AppColors.textMuted),
        _treeItem('📁 pin/', 1, AppColors.warning),
        _treeItem('📁 2026-03-02/', 2, AppColors.textSecondary),
        _treeItem('📄 EMP-001_pin_clock_in_09-00.json', 3, AppColors.textMuted),
        _treeItem('📁 fingerprint/', 1, AppColors.accentSecondary),
        _treeItem('📁 face_id/', 1, AppColors.accent),
      ]),
    );
  }

  Widget _treeItem(String label, int indent, Color color) {
    return Padding(
      padding: EdgeInsets.only(left: indent * 16.0, bottom: 4),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontFamily: 'monospace',
              height: 1.6)),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _shortMonth(String date) {
    try {
      final d = DateTime.parse(date);
      return DateFormat('MMM').format(d).toUpperCase();
    } catch (_) {
      return date.substring(5, 7);
    }
  }

  String _dayNum(String date) {
    try { return DateTime.parse(date).day.toString(); } catch (_) { return '--'; }
  }

  String _year(String date) {
    try { return DateTime.parse(date).year.toString(); } catch (_) { return ''; }
  }

  IconData _methodIcon(String method) {
    switch (method) {
      case 'pin': return Icons.pin_rounded;
      case 'fingerprint': return Icons.fingerprint_rounded;
      case 'face': return Icons.face_retouching_natural;
      case 'qrCode': return Icons.qr_code_rounded;
      default: return Icons.login_rounded;
    }
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'pin': return 'PIN';
      case 'fingerprint': return 'Finger';
      case 'face': return 'Face';
      case 'qrCode': return 'QR';
      default: return method;
    }
  }
}
