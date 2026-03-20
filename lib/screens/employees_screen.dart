// lib/screens/employees_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../models/employee.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _employees = [];
  List<Employee> _filtered = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final employees = await DatabaseService.instance.getAllEmployees();
    if (mounted) {
      setState(() {
        _employees = employees;
        _filtered = employees;
        _loading = false;
      });
    }
  }

  void _filter(String query) {
    setState(() {
      _search = query;
      _filtered = _employees.where((e) {
        final matchSearch = e.fullName.toLowerCase().contains(query.toLowerCase()) ||
            e.employeeId.toLowerCase().contains(query.toLowerCase()) ||
            e.department.toLowerCase().contains(query.toLowerCase());
        return matchSearch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearch(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _EmployeeCard(employee: _filtered[i]),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmployee(),
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: AppColors.primary),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Text('Employees',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              )),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Text('${_filtered.length} total',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: TextField(
        onChanged: _filter,
        decoration: const InputDecoration(
          hintText: 'Search by name, ID, department...',
          prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
        ),
        style: const TextStyle(color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text(
            _search.isEmpty ? 'No employees found' : 'No results for "$_search"',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showAddEmployee() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => const _AddEmployeeSheet(),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  const _EmployeeCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.gradientCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.gradientPrimary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(employee.initials,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  )),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text('${employee.position} · ${employee.department}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    )),
                const SizedBox(height: 4),
                Text(employee.employeeId,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    )),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BioBadge(active: employee.hasFaceEnrolled, icon: Icons.face_rounded),
              const SizedBox(height: 4),
              _BioBadge(active: employee.hasFingerprintEnrolled,
                  icon: Icons.fingerprint_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _BioBadge extends StatelessWidget {
  final bool active;
  final IconData icon;
  const _BioBadge({required this.active, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Icon(icon,
        color: active ? AppColors.success : AppColors.textMuted, size: 18);
  }
}

class _AddEmployeeSheet extends StatefulWidget {
  const _AddEmployeeSheet();

  @override
  State<_AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<_AddEmployeeSheet> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Employee',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              )),
          const SizedBox(height: 20),
          TextField(
            controller: _firstNameCtrl,
            decoration: const InputDecoration(labelText: 'First Name'),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastNameCtrl,
            decoration: const InputDecoration(labelText: 'Last Name'),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Email'),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Add Employee'),
            ),
          ),
        ],
      ),
    );
  }
}
