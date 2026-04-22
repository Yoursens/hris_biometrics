// lib/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ReportsScreen({super.key, this.initialEmployee});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  int _selectedRange = 0;
  final List<String> _ranges = ['This Week', 'This Month', 'This Quarter'];
  
  Map<String, int> _stats = {'present': 0, 'late': 0, 'absent': 0, 'onLeave': 0};
  List<FlSpot> _trendSpots = [];
  bool _loading = true;
  Employee? _employee;
  double _totalEarned = 0.0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final empId = await SecurityService.instance.getCurrentEmployeeId();
      
      Employee? employee = widget.initialEmployee;
      Map<String, int> stats = {'present': 0, 'late': 0, 'absent': 0, 'onLeave': 0};
      List<Attendance> history = [];
      Map<String, dynamic> payroll = {'grossPay': 0.0};

      if (empId != null && !kIsWeb) {
        employee = await DatabaseService.instance.getEmployeeById(empId);
        final s = await DatabaseService.instance.getAttendanceStats(empId);
        stats = {
          'present': s['present'] ?? 0,
          'late': s['late'] ?? 0,
          'absent': s['absent'] ?? 0,
          'onLeave': 0,
        };
        history = await DatabaseService.instance.getAttendanceByEmployee(empId, limit: 10);
        payroll = await DatabaseService.instance.getPayrollSummary(empId, days: 15);
      }
      
      List<FlSpot> spots = [];
      for (int i = 0; i < history.length; i++) {
        double val = history[i].status == AttendanceStatus.present ? 100.0 : 60.0;
        spots.add(FlSpot(i.toDouble(), val));
      }
      
      if (spots.isEmpty) spots = [const FlSpot(0, 0)];

      if (mounted) {
        setState(() {
          _employee = employee;
          _totalEarned = payroll['grossPay'] ?? 0.0;
          _stats = stats;
          _trendSpots = spots.reversed.toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading reports: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 900;
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
                child: Column(
                  children: [
                    _buildHeader(isDesktop),
                    _buildRangeSelector(isDesktop),
                    _buildTabs(isDesktop),
                    Expanded(
                      child: _loading 
                        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                        : TabBarView(
                            controller: _tabCtrl,
                            children: [
                              _buildAttendanceTab(isDesktop),
                              _buildDepartmentTab(isDesktop),
                              _buildExportTab(isDesktop),
                            ],
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 20, 16, 20, 8),
      child: Row(
        children: [
          Text('Reports & Analytics',
              style: TextStyle(fontSize: isDesktop ? 32 : 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector(bool isDesktop) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: List.generate(_ranges.length, (i) {
          final selected = _selectedRange == i;
          return ChoiceChip(
            label: Text(_ranges[i]),
            selected: selected,
            onSelected: (val) {
              setState(() => _selectedRange = i);
              _loadData();
            },
            selectedColor: AppColors.accent,
            backgroundColor: AppColors.card,
            labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.bold),
          );
        }),
      ),
    );
  }

  Widget _buildTabs(bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20),
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: !isDesktop,
        indicatorColor: AppColors.accent,
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textMuted,
        tabs: const [Tab(text: 'Attendance'), Tab(text: 'Department'), Tab(text: 'Export')],
      ),
    );
  }

  Widget _buildAttendanceTab(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 40 : 20),
      child: Column(
        children: [
          if (isDesktop) 
            Row(
              children: [
                _SummaryCard(label: 'Present', value: '${_stats['present']}', icon: Icons.check_circle_rounded, color: AppColors.success),
                const SizedBox(width: 20),
                _SummaryCard(label: 'Late', value: '${_stats['late']}', icon: Icons.schedule_rounded, color: AppColors.warning),
                const SizedBox(width: 20),
                _SummaryCard(label: 'Absent', value: '${_stats['absent']}', icon: Icons.cancel_rounded, color: AppColors.error),
                const SizedBox(width: 20),
                _SummaryCard(label: 'On Leave', value: '${_stats['onLeave']}', icon: Icons.beach_access_rounded, color: AppColors.info),
              ],
            )
          else 
            Column(
              children: [
                Row(
                  children: [
                    _SummaryCard(label: 'Present', value: '${_stats['present']}', icon: Icons.check_circle_rounded, color: AppColors.success),
                    const SizedBox(width: 12),
                    _SummaryCard(label: 'Late', value: '${_stats['late']}', icon: Icons.schedule_rounded, color: AppColors.warning),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SummaryCard(label: 'Absent', value: '${_stats['absent']}', icon: Icons.cancel_rounded, color: AppColors.error),
                    const SizedBox(width: 12),
                    _SummaryCard(label: 'On Leave', value: '${_stats['onLeave']}', icon: Icons.beach_access_rounded, color: AppColors.info),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 32),
          _TrendChart(spots: _trendSpots, isDesktop: isDesktop),
        ],
      ),
    );
  }

  Widget _buildDepartmentTab(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 40 : 20),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.cardBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Performance by Department', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
            const SizedBox(height: 32),
            if (isDesktop)
              Row(
                children: [
                  Expanded(child: _DepartmentRow(data: _DeptData('Corporate Operations', 0.95, AppColors.accent))),
                  const SizedBox(width: 40),
                  Expanded(child: _DepartmentRow(data: _DeptData('Field Logistics', 0.82, AppColors.accentSecondary))),
                ],
              )
            else
              Column(
                children: [
                  _DepartmentRow(data: _DeptData('Corporate Operations', 0.95, AppColors.accent)),
                  const SizedBox(height: 16),
                  _DepartmentRow(data: _DeptData('Field Logistics', 0.82, AppColors.accentSecondary)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportTab(bool isDesktop) {
    final formats = [
      _ExportFormat('PDF Report', 'Professional document for printing', Icons.picture_as_pdf_rounded, AppColors.error),
      _ExportFormat('Excel Sheet', 'Complete data for spreadsheet analysis', Icons.table_chart_rounded, AppColors.success),
      _ExportFormat('CSV Data', 'Raw text format for system import', Icons.data_array_rounded, AppColors.accentSecondary),
    ];

    return Padding(
      padding: EdgeInsets.all(isDesktop ? 40 : 20),
      child: isDesktop 
        ? Row(
            children: formats.map((f) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _buildExportCard(f, true),
              ),
            )).toList(),
          )
        : ListView(
            children: formats.map((f) => _buildExportCard(f, false)).toList(),
          ),
    );
  }

  Widget _buildExportCard(_ExportFormat f, bool isDesktop) {
    return InkWell(
      onTap: () => _showExportPreview(f),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: f.color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: f.color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(f.icon, color: f.color, size: 40),
            const SizedBox(height: 16),
            Text(f.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(f.sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: f.color, borderRadius: BorderRadius.circular(10)),
              child: const Text('GENERATE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportPreview(_ExportFormat f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ExportPreviewSheet(format: f, employee: _employee, range: _ranges[_selectedRange], totalEarned: _totalEarned),
    );
  }
}

class _ExportPreviewSheet extends StatefulWidget {
  final _ExportFormat format;
  final Employee? employee;
  final String range;
  final double totalEarned;
  const _ExportPreviewSheet({required this.format, this.employee, required this.range, required this.totalEarned});

  @override
  State<_ExportPreviewSheet> createState() => _ExportPreviewSheetState();
}

class _ExportPreviewSheetState extends State<_ExportPreviewSheet> {
  bool _exporting = false;

  Future<void> _handleExport() async {
    setState(() => _exporting = true);
    if (widget.employee != null && !kIsWeb) {
      final payroll = await DatabaseService.instance.getPayrollSummary(widget.employee!.id, days: 15);
      await DatabaseService.instance.savePayrollExportFile(widget.employee!, payroll);
      try {
        await FirebaseFirestore.instance.collection('mobile_exports').add({
          'employee_id': widget.employee!.employeeId,
          'employee_name': widget.employee!.fullName,
          'report_type': widget.format.label,
          'total_earned': widget.totalEarned,
          'range': widget.range,
          'exported_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Error syncing export to admin: $e');
      }
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kIsWeb ? '${widget.format.label} generation simulated on web' : '${widget.format.label} exported ✓'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '₱');
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(widget.format.icon, color: widget.format.color, size: 24),
            const SizedBox(width: 12),
            const Text('Ready to Export', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 32),
          _previewRow('Format', widget.format.label),
          _previewRow('Period', widget.range),
          _previewRow('Earnings', fmt.format(widget.totalEarned)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _exporting ? null : _handleExport,
              style: ElevatedButton.styleFrom(backgroundColor: widget.format.color),
              child: _exporting ? const CircularProgressIndicator(color: Colors.white) : const Text('DOWNLOAD NOW'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.1))),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textMuted)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<FlSpot> spots;
  final bool isDesktop;
  const _TrendChart({required this.spots, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ATTENDANCE TREND', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.textMuted, letterSpacing: 1)),
          const SizedBox(height: 32),
          SizedBox(
            height: isDesktop ? 300 : 200,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.accent,
                    barWidth: 3,
                    belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: 0.1)),
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeptData {
  final String name;
  final double rate;
  final Color color;
  const _DeptData(this.name, this.rate, this.color);
}

class _DepartmentRow extends StatelessWidget {
  final _DeptData data;
  const _DepartmentRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(data.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const Spacer(),
              Text('${(data.rate * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: data.color)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: data.rate, backgroundColor: data.color.withValues(alpha: 0.1), valueColor: AlwaysStoppedAnimation<Color>(data.color), minHeight: 8, borderRadius: BorderRadius.circular(10)),
        ],
      ),
    );
  }
}

class _ExportFormat {
  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  const _ExportFormat(this.label, this.sub, this.icon, this.color);
}
