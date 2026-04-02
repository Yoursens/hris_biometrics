// lib/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

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
    setState(() => _loading = true);
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    if (empId == null) return;

    final employee = await DatabaseService.instance.getEmployeeById(empId);
    final stats = await DatabaseService.instance.getAttendanceStats(empId);
    final history = await DatabaseService.instance.getAttendanceByEmployee(empId, limit: 10);
    final payroll = await DatabaseService.instance.getPayrollSummary(empId, days: 15);
    
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
        _stats = {
          'present': stats['present'] ?? 0,
          'late': stats['late'] ?? 0,
          'absent': stats['absent'] ?? 0,
          'onLeave': 0,
        };
        _trendSpots = spots.reversed.toList();
        _loading = false;
      });
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
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildRangeSelector(),
            _buildTabs(),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildAttendanceTab(),
                      _buildDepartmentTab(),
                      _buildExportTab(),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Text('Reports',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: List.generate(_ranges.length, (i) {
          final selected = _selectedRange == i;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedRange = i);
              _loadData();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorder),
              ),
              child: Text(_ranges[i],
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.primary : AppColors.textSecondary)),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabCtrl,
      indicatorColor: AppColors.accent,
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.textMuted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      tabs: const [Tab(text: 'Attendance'), Tab(text: 'Department'), Tab(text: 'Export')],
    );
  }

  Widget _buildAttendanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryCard(label: 'Total Present', value: '${_stats['present']}', icon: Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: 12),
              _SummaryCard(label: 'Late Arrivals', value: '${_stats['late']}', icon: Icons.schedule_rounded, color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryCard(label: 'Absences', value: '${_stats['absent']}', icon: Icons.cancel_rounded, color: AppColors.error),
              const SizedBox(width: 12),
              _SummaryCard(label: 'On Leave', value: '${_stats['onLeave']}', icon: Icons.beach_access_rounded, color: AppColors.info),
            ],
          ),
          const SizedBox(height: 20),
          _TrendChart(spots: _trendSpots),
        ],
      ),
    );
  }

  Widget _buildDepartmentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: AppColors.gradientCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Department Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            _DepartmentRow(data: _DeptData('Corporate', 0.95, AppColors.accent)),
            _DepartmentRow(data: _DeptData('Field Logistics', 0.82, AppColors.accentSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildExportTab() {
    final formats = [
      _ExportFormat('PDF Report', 'Professional document for printing', Icons.picture_as_pdf_rounded, AppColors.error),
      _ExportFormat('Excel Sheet', 'Complete data for spreadsheet analysis', Icons.table_chart_rounded, AppColors.success),
      _ExportFormat('CSV Data', 'Raw text format for system import', Icons.data_array_rounded, AppColors.accentSecondary),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: formats.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _showExportPreview(f),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: f.color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: f.color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(f.icon, color: f.color, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text(f.sub, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                  ),
                  Icon(Icons.remove_red_eye_outlined, color: f.color, size: 18),
                ],
              ),
            ),
          ),
        )).toList(),
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
    
    // Simulate real database extraction including the "money" (earnings) data
    if (widget.employee != null) {
      final payroll = await DatabaseService.instance.getPayrollSummary(widget.employee!.id, days: 15);
      await DatabaseService.instance.savePayrollExportFile(widget.employee!, payroll);
    }
    
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.format.label} with Total Earnings (₱${widget.totalEarned.toStringAsFixed(2)}) exported ✓'), 
          backgroundColor: AppColors.success
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '₱');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(widget.format.icon, color: widget.format.color, size: 20),
            const SizedBox(width: 12),
            const Text('Export Preview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 24),
          _previewInfo('FILE TYPE', widget.format.label),
          _previewInfo('REPORT RANGE', widget.range.toUpperCase()),
          _previewInfo('EMPLOYEE NAME', widget.employee?.fullName ?? 'N/A'),
          _previewInfo('TOTAL EARNINGS', fmt.format(widget.totalEarned)),
          _previewInfo('DATA FIELDS', 'Date, Time In, Time Out, Hours, Earnings (₱)'),
          const SizedBox(height: 24),
          const Divider(color: AppColors.cardBorder),
          const SizedBox(height: 12),
          const Text('The exported file will include a detailed breakdown of daily hours and calculated salary for this period.', 
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _exporting ? null : _handleExport,
              style: ElevatedButton.styleFrom(backgroundColor: widget.format.color, foregroundColor: Colors.white),
              child: _exporting 
                ? const CircularProgressIndicator(color: Colors.white)
                : Text('Confirm & Download ${widget.format.label.split(' ')[0]}'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _previewInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<FlSpot> spots;
  const _TrendChart({required this.spots});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppColors.gradientCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Attendance Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                backgroundColor: Colors.transparent,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.accent,
                    barWidth: 2.5,
                    belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.accent.withOpacity(0.3), AppColors.accent.withOpacity(0.0)])),
                    dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(radius: 4, color: AppColors.accent, strokeWidth: 2, strokeColor: AppColors.primary)),
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
              Text(data.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Text('${(data.rate * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: data.color)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: data.rate,
            backgroundColor: data.color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(data.color),
            borderRadius: BorderRadius.circular(4),
            minHeight: 8,
          ),
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
