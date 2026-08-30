import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

// Brand Design Tokens (matching app identity)
const Color kPrimaryBlue = Color(0xFF0052CC);
const Color kSecondaryBlue = Color(0xFF1E6BFF);
const Color kLightBlue = Color(0xFFE8F0FE);
const Color kBackgroundSlate = Color(0xFFF7F9FC);
const Color kCardBorder = Color(0xFFE2E8F0);
const Color kTextPrimary = Color(0xFF0F172A);
const Color kTextSecondary = Color(0xFF64748B);

const Color kSuccessGreen = Color(0xFF10B981);
const Color kWarningAmber = Color(0xFFF59E0B);
const Color kDangerRed = Color(0xFFEF4444);
const Color kPurpleAccent = Color(0xFF8B5CF6);

class RouteOptimizerScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const RouteOptimizerScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<RouteOptimizerScreen> createState() => _RouteOptimizerScreenState();
}

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen>
    with SingleTickerProviderStateMixin {
  // Optimization weights
  double _cost = 0.40;
  double _time = 0.30;
  double _capacity = 0.20;
  double _condition = 0.10;

  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  // UX Controls
  int _selectedTab = 0; // 0: Overview & Assignments, 1: Matrix Heatmap, 2: Analytics
  String _searchQuery = '';
  String _fitFilter = 'ALL'; // ALL, GOOD, OVERSIZED, OVERCAPACITY
  String _chartMetric = 'COST'; // COST, CO2, TIME, SCORE
  int? _selectedMatrixBusIndex;
  int? _selectedMatrixRouteIndex;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$kBackendBaseUrl/admin/optimize-routes').replace(
        queryParameters: {
          'school_id': widget.schoolId,
          'w_cost': _cost.toStringAsFixed(2),
          'w_time': _time.toStringAsFixed(2),
          'w_capacity': _capacity.toStringAsFixed(2),
          'w_condition': _condition.toStringAsFixed(2),
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw Exception('Invalid data structure returned from backend');
      }

      if (mounted) {
        setState(() {
          _data = body;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not fetch optimization recommendations.\n'
              'Verify backend connection at $kBackendBaseUrl';
          _loading = false;
        });
      }
    }
  }

  // Helper Getters for safe parsing
  double _num(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  List<dynamic> get _assignments => (_data?['assignments'] as List?) ?? const [];
  List<dynamic> get _buses => (_data?['buses'] as List?) ?? const [];
  List<dynamic> get _routes => (_data?['routes'] as List?) ?? const [];
  List<dynamic> get _matrix => (_data?['matrix'] as List?) ?? const [];

  double get _normalizedCostWeight {
    final sum = _cost + _time + _capacity + _condition;
    return sum > 0 ? (_cost / sum) * 100 : 0;
  }

  double get _normalizedTimeWeight {
    final sum = _cost + _time + _capacity + _condition;
    return sum > 0 ? (_time / sum) * 100 : 0;
  }

  double get _normalizedCapacityWeight {
    final sum = _cost + _time + _capacity + _condition;
    return sum > 0 ? (_capacity / sum) * 100 : 0;
  }

  double get _normalizedConditionWeight {
    final sum = _cost + _time + _capacity + _condition;
    return sum > 0 ? (_condition / sum) * 100 : 0;
  }

  double get _avgSuitabilityScore {
    if (_assignments.isEmpty) return 0.0;
    final total = _assignments.fold<double>(
      0.0,
      (sum, item) => sum + _num((item as Map)['score']),
    );
    return (total / _assignments.length) * 100;
  }

  int get _overcapacityCount {
    return _assignments.where((a) {
      final fit = (a as Map)['capacity_fit']?.toString() ?? '';
      return fit == 'Overcapacity';
    }).length;
  }

  List<dynamic> get _filteredAssignments {
    return _assignments.where((a) {
      final map = a as Map<String, dynamic>;
      final busLabel = ((map['bus'] as Map?)?['label'] ?? '').toString().toLowerCase();
      final routeLabel = ((map['route'] as Map?)?['label'] ?? '').toString().toLowerCase();
      final fit = (map['capacity_fit'] ?? '').toString();

      final matchesQuery = _searchQuery.isEmpty ||
          busLabel.contains(_searchQuery.toLowerCase()) ||
          routeLabel.contains(_searchQuery.toLowerCase());

      bool matchesFilter = true;
      if (_fitFilter == 'GOOD') {
        matchesFilter = fit == 'Good fit';
      } else if (_fitFilter == 'OVERSIZED') {
        matchesFilter = fit.contains('oversized') || fit.contains('Oversized');
      } else if (_fitFilter == 'OVERCAPACITY') {
        matchesFilter = fit == 'Overcapacity';
      }

      return matchesQuery && matchesFilter;
    }).toList();
  }

  void _applyPreset(double cost, double time, double capacity, double condition) {
    setState(() {
      _cost = cost;
      _time = time;
      _capacity = capacity;
      _condition = condition;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundSlate,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _loading && _data == null
                  ? _buildLoadingState()
                  : _error != null && _data == null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          color: kSecondaryBlue,
                          child: IndexedStack(
                            index: _selectedTab,
                            children: [
                              _buildOverviewTab(),
                              _buildMatrixTab(),
                              _buildAnalyticsTab(),
                            ],
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── APP BAR & TAB NAVIGATION ─────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: kPrimaryBlue,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 20, color: Color(0xFFFFD700)),
              const SizedBox(width: 8),
              const Text(
                'AI Route Optimizer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          Text(
            widget.schoolName,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Re-run Optimization',
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _fetch,
        ),
        IconButton(
          tooltip: 'Optimization Logic Info',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: _showInfoDialog,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: kPrimaryBlue,
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3.5,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard_customize_outlined, size: 20),
            text: 'Overview',
          ),
          Tab(
            icon: Icon(Icons.grid_on_rounded, size: 20),
            text: 'Suitability Grid',
          ),
          Tab(
            icon: Icon(Icons.insights_rounded, size: 20),
            text: 'Fleet Analytics',
          ),
        ],
      ),
    );
  }

  // ─── TAB 1: OVERVIEW & ASSIGNMENTS ─────────────────────────────────

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildExecutiveKPIHeader(),
        const SizedBox(height: 16),
        _buildWeightControlPanel(),
        const SizedBox(height: 20),
        _buildAssignmentSectionHeader(),
        const SizedBox(height: 12),
        if (_filteredAssignments.isEmpty)
          _buildEmptyAssignmentsView()
        else
          ..._filteredAssignments.map((a) => _buildAssignmentCard(Map<String, dynamic>.from(a as Map))),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildExecutiveKPIHeader() {
    final totalCost = _num(_data?['total_diesel_cost']);
    final totalCO2 = _num(_data?['total_co2_kg']);
    final score = _avgSuitabilityScore;
    final unassignedBuses = (_data?['unassigned_bus_count'] as num?)?.toInt() ?? 0;
    final unassignedRoutes = (_data?['unassigned_route_count'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        if (_overcapacityCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: kDangerRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kDangerRed.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: kDangerRed, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Attention Required: $_overcapacityCount bus assignment(s) flagged for student overcapacity.',
                    style: const TextStyle(
                      color: kDangerRed,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                title: 'Est. Fuel Cost',
                value: '₹${totalCost.toStringAsFixed(2)}',
                subtitle: 'Across ${_assignments.length} assigned routes',
                icon: Icons.local_gas_station_rounded,
                accentColor: kSecondaryBlue,
                bgGradient: [const Color(0xFF1E6BFF), const Color(0xFF0052CC)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                title: 'CO₂ Footprint',
                value: '${totalCO2.toStringAsFixed(1)} kg',
                subtitle: 'Estimated diesel emissions',
                icon: Icons.eco_rounded,
                accentColor: kSuccessGreen,
                bgGradient: [const Color(0xFF10B981), const Color(0xFF059669)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                title: 'Fleet Match Index',
                value: '${score.toStringAsFixed(1)}%',
                subtitle: 'Hungarian Optimization Score',
                icon: Icons.speed_rounded,
                accentColor: kPurpleAccent,
                bgGradient: [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                title: 'Unassigned Fleet',
                value: '$unassignedBuses Bus / $unassignedRoutes Route',
                subtitle: 'Pending route pairing',
                icon: Icons.bus_alert_rounded,
                accentColor: (unassignedBuses > 0 || unassignedRoutes > 0) ? kWarningAmber : kTextSecondary,
                bgGradient: (unassignedBuses > 0 || unassignedRoutes > 0)
                    ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                    : [const Color(0xFF64748B), const Color(0xFF475569)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required List<Color> bgGradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: bgGradient),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
              letterSpacing: -0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildWeightControlPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kLightBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded, color: kSecondaryBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Optimization Priority Weights',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary,
                        ),
                      ),
                      Text(
                        'Adjust algorithms to prioritize cost, speed, capacity or fleet health',
                        style: TextStyle(fontSize: 11, color: kTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Presets Bar
            const Text(
              'QUICK PRESETS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: kTextSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPresetChip('⚡ Balanced', 0.40, 0.30, 0.20, 0.10),
                  _buildPresetChip('💰 Cost Saver', 0.65, 0.15, 0.10, 0.10),
                  _buildPresetChip('🌱 Eco & Green', 0.25, 0.20, 0.30, 0.25),
                  _buildPresetChip('⏱️ Express Time', 0.20, 0.60, 0.10, 0.10),
                ],
              ),
            ),

            const Divider(height: 24),

            // Visual Weight Distribution Bar
            _buildNormalizedWeightDistributionBar(),
            const SizedBox(height: 16),

            // Weight Sliders Grid
            _buildWeightSliderRow(
              label: 'Fuel & Diesel Cost',
              value: _cost,
              percentage: _normalizedCostWeight,
              color: kSecondaryBlue,
              icon: Icons.local_gas_station_rounded,
              onChanged: (v) => setState(() => _cost = v),
            ),
            _buildWeightSliderRow(
              label: 'Travel Time & Commute',
              value: _time,
              percentage: _normalizedTimeWeight,
              color: kPurpleAccent,
              icon: Icons.timer_rounded,
              onChanged: (v) => setState(() => _time = v),
            ),
            _buildWeightSliderRow(
              label: 'Student Capacity Fit',
              value: _capacity,
              percentage: _normalizedCapacityWeight,
              color: kSuccessGreen,
              icon: Icons.groups_rounded,
              onChanged: (v) => setState(() => _capacity = v),
            ),
            _buildWeightSliderRow(
              label: 'Bus Maintenance Condition',
              value: _condition,
              percentage: _normalizedConditionWeight,
              color: kWarningAmber,
              icon: Icons.build_circle_rounded,
              onChanged: (v) => setState(() => _condition = v),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _loading ? null : _fetch,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text(
                  'Run Hungarian Optimization',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(
    String label,
    double c,
    double t,
    double cap,
    double cond,
  ) {
    final isSelected =
        (_cost - c).abs() < 0.02 &&
        (_time - t).abs() < 0.02 &&
        (_capacity - cap).abs() < 0.02 &&
        (_condition - cond).abs() < 0.02;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : kTextPrimary,
        ),
        selectedColor: kSecondaryBlue,
        backgroundColor: kLightBlue.withOpacity(0.5),
        showCheckmark: false,
        onSelected: (_) => _applyPreset(c, t, cap, cond),
      ),
    );
  }

  Widget _buildNormalizedWeightDistributionBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'NORMALIZED WEIGHT RATIO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: kTextSecondary,
              ),
            ),
            Text(
              'Cost ${_normalizedCostWeight.toStringAsFixed(0)}% | Time ${_normalizedTimeWeight.toStringAsFixed(0)}% | Cap ${_normalizedCapacityWeight.toStringAsFixed(0)}% | Cond ${_normalizedConditionWeight.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 10, color: kSecondaryBlue, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(1, _normalizedCostWeight.round()),
                  child: Container(color: kSecondaryBlue),
                ),
                Expanded(
                  flex: math.max(1, _normalizedTimeWeight.round()),
                  child: Container(color: kPurpleAccent),
                ),
                Expanded(
                  flex: math.max(1, _normalizedCapacityWeight.round()),
                  child: Container(color: kSuccessGreen),
                ),
                Expanded(
                  flex: math.max(1, _normalizedConditionWeight.round()),
                  child: Container(color: kWarningAmber),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeightSliderRow({
    required String label,
    required double value,
    required double percentage,
    required Color color,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${value.toStringAsFixed(2)} (${percentage.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withOpacity(0.15),
              thumbColor: color,
              overlayColor: color.withOpacity(0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentSectionHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Optimal Pairings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kLightBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_filteredAssignments.length} / ${_assignments.length} assigned',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Search & Filter controls
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search bus or route...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kCardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kCardBorder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kCardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _fitFilter,
                  icon: const Icon(Icons.filter_list_rounded, size: 20),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Fits')),
                    DropdownMenuItem(value: 'GOOD', child: Text('Good Fit')),
                    DropdownMenuItem(value: 'OVERSIZED', child: Text('Oversized')),
                    DropdownMenuItem(value: 'OVERCAPACITY', child: Text('Overcapacity')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _fitFilter = v);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment) {
    final busMap = assignment['bus'] as Map? ?? {};
    final routeMap = assignment['route'] as Map? ?? {};
    final busLabel = busMap['label']?.toString() ?? 'Unknown Bus';
    final routeLabel = routeMap['label']?.toString() ?? 'Unknown Route';

    final score = _num(assignment['score']);
    final cost = _num(assignment['diesel_cost']);
    final timeHours = _num(assignment['travel_time_hours']);
    final co2 = _num(assignment['co2_kg']);
    final fitLabel = assignment['capacity_fit']?.toString() ?? 'N/A';
    final explanation = assignment['explanation']?.toString() ?? '';

    final isOvercapacity = fitLabel == 'Overcapacity';
    final isGoodFit = fitLabel == 'Good fit';

    Color fitColor = kSecondaryBlue;
    if (isOvercapacity) fitColor = kDangerRed;
    else if (isGoodFit) fitColor = kSuccessGreen;
    else if (fitLabel.contains('Oversized')) fitColor = kWarningAmber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOvercapacity ? kDangerRed.withOpacity(0.5) : kCardBorder,
          width: isOvercapacity ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isOvercapacity ? kDangerRed.withOpacity(0.06) : kLightBlue.withOpacity(0.4),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isOvercapacity
                      ? kDangerRed.withOpacity(0.15)
                      : kSecondaryBlue.withOpacity(0.15),
                  child: Icon(
                    Icons.directions_bus_rounded,
                    color: isOvercapacity ? kDangerRed : kSecondaryBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              busLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kTextPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded, size: 16, color: kTextSecondary),
                          ),
                          Flexible(
                            child: Text(
                              routeLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryBlue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Optimized match pairing',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Score Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color.lerp(kDangerRed, kSuccessGreen, score),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Color.lerp(kDangerRed, kSuccessGreen, score)!.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Text(
                    '${(score * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metrics grid
                Row(
                  children: [
                    _buildSubMetricTile(
                      icon: Icons.local_gas_station_rounded,
                      label: 'Fuel Cost',
                      value: '₹${cost.toStringAsFixed(2)}',
                      color: kSecondaryBlue,
                    ),
                    _buildSubMetricTile(
                      icon: Icons.timer_rounded,
                      label: 'Commute Time',
                      value: '${timeHours.toStringAsFixed(2)} hrs',
                      color: kPurpleAccent,
                    ),
                    _buildSubMetricTile(
                      icon: Icons.eco_rounded,
                      label: 'CO₂ Emission',
                      value: '${co2.toStringAsFixed(2)} kg',
                      color: kSuccessGreen,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Capacity Fit Badge
                Row(
                  children: [
                    const Text(
                      'Capacity Fit: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kTextSecondary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: fitColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: fitColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOvercapacity
                                ? Icons.warning_rounded
                                : isGoodFit
                                    ? Icons.check_circle_rounded
                                    : Icons.info_rounded,
                            size: 14,
                            color: fitColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fitLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: fitColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (explanation.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBackgroundSlate,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kCardBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.psychology_rounded,
                          size: 18,
                          color: kPrimaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            explanation,
                            style: const TextStyle(
                              fontSize: 12,
                              color: kTextPrimary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: kTextSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAssignmentsView() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No matching route pairings found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try adjusting your search terms or filter criteria.',
            style: TextStyle(color: kTextSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── TAB 2: SUITABILITY MATRIX HEATMAP ───────────────────────────────

  Widget _buildMatrixTab() {
    if (_buses.isEmpty || _routes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [_buildEmptyAssignmentsView()],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Full Fleet Suitability Grid',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary,
                        ),
                      ),
                      Text(
                        'Evaluated score for every Bus × Route pair (0.0 to 1.0)',
                        style: TextStyle(fontSize: 11, color: kTextSecondary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kLightBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_buses.length} Buses × ${_routes.length} Routes',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Heatmap legend
              Row(
                children: [
                  const Text('Low Match', style: TextStyle(fontSize: 10, color: kTextSecondary)),
                  const SizedBox(width: 6),
                  Container(
                    width: 80,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [kDangerRed, kWarningAmber, kSuccessGreen],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Optimal Match', style: TextStyle(fontSize: 10, color: kTextSecondary)),
                ],
              ),
              const SizedBox(height: 16),

              // Heatmap Table
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(110),
                  border: TableBorder.all(color: Colors.grey.shade300, width: 0.8),
                  children: [
                    // Header Row
                    TableRow(
                      decoration: BoxDecoration(color: kLightBlue.withOpacity(0.5)),
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: Text(
                            'Bus \\ Route',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: kPrimaryBlue,
                            ),
                          ),
                        ),
                        ..._routes.map((r) => Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                (r as Map)['label']?.toString() ?? 'Route',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: kTextPrimary,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                    ),

                    // Bus Rows
                    ...List.generate(_buses.length, (busIdx) {
                      final row = busIdx < _matrix.length ? _matrix[busIdx] as List : const [];
                      final busLabel = (_buses[busIdx] as Map)['label']?.toString() ?? 'Bus ${busIdx + 1}';

                      return TableRow(
                        children: [
                          // Row Header
                          Container(
                            color: kLightBlue.withOpacity(0.2),
                            padding: const EdgeInsets.all(10),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              busLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: kTextPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // Score cells
                          ...List.generate(_routes.length, (routeIdx) {
                            final score = routeIdx < row.length ? _num(row[routeIdx]) : 0.0;
                            final isSelected = _selectedMatrixBusIndex == busIdx &&
                                _selectedMatrixRouteIndex == routeIdx;

                            // Check if this pair is actually assigned by Hungarian algorithm
                            final isAssigned = _assignments.any((a) {
                              final bId = (a as Map)['bus']?['id'];
                              final rId = a['route']?['id'];
                              return bId == (_buses[busIdx] as Map)['id'] &&
                                  rId == (_routes[routeIdx] as Map)['id'];
                            });

                            final cellBg = Color.lerp(
                              kDangerRed.withOpacity(0.7),
                              kSuccessGreen,
                              score,
                            )!;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedMatrixBusIndex = busIdx;
                                  _selectedMatrixRouteIndex = routeIdx;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: 50,
                                decoration: BoxDecoration(
                                  color: cellBg,
                                  border: isSelected
                                      ? Border.all(color: Colors.black, width: 2.5)
                                      : null,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Text(
                                      score.toStringAsFixed(2),
                                      style: TextStyle(
                                        color: score > 0.45 ? Colors.white : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (isAssigned)
                                      Positioned(
                                        top: 3,
                                        right: 3,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.star_rounded,
                                            size: 10,
                                            color: kPrimaryBlue,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              if (_selectedMatrixBusIndex != null && _selectedMatrixRouteIndex != null) ...[
                const SizedBox(height: 16),
                _buildSelectedMatrixCellDetails(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedMatrixCellDetails() {
    final busIdx = _selectedMatrixBusIndex!;
    final routeIdx = _selectedMatrixRouteIndex!;
    if (busIdx >= _buses.length || routeIdx >= _routes.length) {
      return const SizedBox.shrink();
    }

    final busLabel = (_buses[busIdx] as Map)['label']?.toString() ?? 'Bus';
    final routeLabel = (_routes[routeIdx] as Map)['label']?.toString() ?? 'Route';
    final row = busIdx < _matrix.length ? _matrix[busIdx] as List : const [];
    final score = routeIdx < row.length ? _num(row[routeIdx]) : 0.0;

    final assignedMatch = _assignments.firstWhere(
      (a) =>
          (a as Map)['bus']?['id'] == (_buses[busIdx] as Map)['id'] &&
          a['route']?['id'] == (_routes[routeIdx] as Map)['id'],
      orElse: () => null,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kLightBlue.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSecondaryBlue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.touch_app_rounded, size: 18, color: kSecondaryBlue),
              const SizedBox(width: 6),
              Text(
                'Inspecting Pair: $busLabel × $routeLabel',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Text(
                'Score: ${score.toStringAsFixed(4)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryBlue),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (assignedMatch != null)
            Row(
              children: [
                const Icon(Icons.stars_rounded, size: 14, color: kSuccessGreen),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Selected by Hungarian Algorithm as optimal assignment!',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            )
          else
            const Text(
              'Not selected in global optimal assignment run.',
              style: TextStyle(fontSize: 11, color: kTextSecondary),
            ),
        ],
      ),
    );
  }

  // ─── TAB 3: FLEET ANALYTICS & CHARTS ────────────────────────────────

  Widget _buildAnalyticsTab() {
    if (_assignments.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [_buildEmptyAssignmentsView()],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOperationalForecastHeader(),
        const SizedBox(height: 16),
        _buildChartMetricToggleCard(),
        const SizedBox(height: 16),
        _buildBarChartCard(),
        const SizedBox(height: 16),
        _buildScoreVsTimeTrendChart(),
        const SizedBox(height: 16),
        _buildCapacityFitDonutCard(),
        const SizedBox(height: 16),
        _buildFleetEfficiencyLeaderboard(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildOperationalForecastHeader() {
    final dailyCost = _num(_data?['total_diesel_cost']);
    final dailyCO2 = _num(_data?['total_co2_kg']);

    // Projections for 22 operational school days per month
    final monthlyCost = dailyCost * 22;
    final monthlyCO2 = dailyCO2 * 22;
    final annualTreesNeeded = (monthlyCO2 * 12) / 21.0; // 1 tree absorbs ~21kg CO2/year

    final avgTimeMins = _assignments.isNotEmpty
        ? (_assignments.fold<double>(0.0, (s, a) => s + _num((a as Map)['travel_time_hours'])) /
                _assignments.length) *
            60
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
            color: kPrimaryBlue.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kLightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.analytics_rounded, color: kPrimaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operational Projections & Environmental Impact',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary,
                    ),
                  ),
                  Text(
                    'Estimated 22-day monthly school fleet forecast',
                    style: TextStyle(fontSize: 11, color: kTextSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildForecastSubCard(
                  label: 'Est. Monthly Fuel',
                  value: '₹${monthlyCost.toStringAsFixed(0)}',
                  detail: '₹${dailyCost.toStringAsFixed(2)} / day',
                  icon: Icons.calendar_month_rounded,
                  color: kSecondaryBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildForecastSubCard(
                  label: 'Est. Monthly CO₂',
                  value: '${monthlyCO2.toStringAsFixed(0)} kg',
                  detail: '${dailyCO2.toStringAsFixed(1)} kg / day',
                  icon: Icons.cloud_outlined,
                  color: kSuccessGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildForecastSubCard(
                  label: 'Avg. Commute Time',
                  value: '${avgTimeMins.toStringAsFixed(0)} mins',
                  detail: 'Per active bus route',
                  icon: Icons.timer_outlined,
                  color: kPurpleAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildForecastSubCard(
                  label: 'Eco Carbon Offset',
                  value: '~${annualTreesNeeded.toStringAsFixed(0)} Trees',
                  detail: 'Annual offset balance',
                  icon: Icons.nature_people_rounded,
                  color: kWarningAmber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForecastSubCard({
    required String label,
    required String value,
    required String detail,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: kTextSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChartMetricToggleCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Comparative Fleet Metric Selection',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 2),
          const Text(
            'Select metric to visualize across assigned buses',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'COST',
                  label: Text('Fuel (₹)', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.local_gas_station_rounded, size: 14),
                ),
                ButtonSegment(
                  value: 'CO2',
                  label: Text('CO₂ (kg)', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.eco_rounded, size: 14),
                ),
                ButtonSegment(
                  value: 'TIME',
                  label: Text('Time (hrs)', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.timer_rounded, size: 14),
                ),
                ButtonSegment(
                  value: 'SCORE',
                  label: Text('Match Score', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.star_rounded, size: 14),
                ),
              ],
              selected: {_chartMetric},
              onSelectionChanged: (set) {
                setState(() => _chartMetric = set.first);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChartCard() {
    final values = _assignments.map((a) {
      final map = a as Map;
      if (_chartMetric == 'COST') return _num(map['diesel_cost']);
      if (_chartMetric == 'CO2') return _num(map['co2_kg']);
      if (_chartMetric == 'TIME') return _num(map['travel_time_hours']);
      return _num(map['score']) * 100;
    }).toList();

    final maxVal = values.isNotEmpty ? values.reduce(math.max) : 1.0;

    String titleText = 'Diesel Fuel Expense (₹) by Bus';
    Color barColor = kSecondaryBlue;
    if (_chartMetric == 'CO2') {
      titleText = 'Carbon Emissions (kg CO₂) by Bus';
      barColor = kSuccessGreen;
    } else if (_chartMetric == 'TIME') {
      titleText = 'Travel Time (Hours) by Bus';
      barColor = kPurpleAccent;
    } else if (_chartMetric == 'SCORE') {
      titleText = 'Hungarian Optimization Match Score (%)';
      barColor = kPrimaryBlue;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleText,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                maxY: maxVal == 0 ? 10 : maxVal * 1.25,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) {
                        String formatted = value.toInt().toString();
                        if (_chartMetric == 'COST') formatted = '₹${value.toInt()}';
                        if (_chartMetric == 'CO2') formatted = '${value.toStringAsFixed(1)}kg';
                        if (_chartMetric == 'TIME') formatted = '${value.toStringAsFixed(1)}h';
                        if (_chartMetric == 'SCORE') formatted = '${value.toInt()}%';

                        return Text(
                          formatted,
                          style: const TextStyle(fontSize: 10, color: kTextSecondary),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _assignments.length) {
                          return const SizedBox.shrink();
                        }
                        final busLabel =
                            ((_assignments[idx] as Map)['bus'] as Map?)?['label']?.toString() ??
                                'B$idx';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            busLabel,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(_assignments.length, (i) {
                  final val = values[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: val,
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [barColor, barColor.withOpacity(0.7)],
                        ),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreVsTimeTrendChart() {
    final spots = List.generate(_assignments.length, (i) {
      final scorePct = _num((_assignments[i] as Map)['score']) * 100;
      return FlSpot(i.toDouble(), scorePct);
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Optimization Score Trend Across Fleet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    'Evaluated match quality per assigned bus route',
                    style: TextStyle(fontSize: 11, color: kTextSecondary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kPurpleAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Hungarian Curve',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: kPurpleAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(fontSize: 10, color: kTextSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= _assignments.length) return const SizedBox.shrink();
                        final busLabel =
                            ((_assignments[i] as Map)['bus'] as Map?)?['label']?.toString() ??
                                'B$i';
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            busLabel,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: kPurpleAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 5,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: kPurpleAccent,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          kPurpleAccent.withOpacity(0.3),
                          kPurpleAccent.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityFitDonutCard() {
    int goodFit = 0;
    int oversized = 0;
    int overcapacity = 0;

    for (var a in _assignments) {
      final fit = (a as Map)['capacity_fit']?.toString() ?? '';
      if (fit == 'Good fit') goodFit++;
      else if (fit == 'Overcapacity') overcapacity++;
      else if (fit.contains('oversized') || fit.contains('Oversized')) oversized++;
    }

    final total = _assignments.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seating & Capacity Distribution Donut',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 2),
          const Text(
            'Visual proportion of route seating occupancy classifications',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Pie Chart
              SizedBox(
                width: 140,
                height: 140,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 40,
                    sections: [
                      if (goodFit > 0)
                        PieChartSectionData(
                          color: kSuccessGreen,
                          value: goodFit.toDouble(),
                          title: '${((goodFit / total) * 100).toStringAsFixed(0)}%',
                          radius: 30,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      if (oversized > 0)
                        PieChartSectionData(
                          color: kWarningAmber,
                          value: oversized.toDouble(),
                          title: '${((oversized / total) * 100).toStringAsFixed(0)}%',
                          radius: 30,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      if (overcapacity > 0)
                        PieChartSectionData(
                          color: kDangerRed,
                          value: overcapacity.toDouble(),
                          title: '${((overcapacity / total) * 100).toStringAsFixed(0)}%',
                          radius: 30,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Legend Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDonutLegendItem(
                      color: kSuccessGreen,
                      title: 'Good fit',
                      count: goodFit,
                      total: total,
                    ),
                    const SizedBox(height: 8),
                    _buildDonutLegendItem(
                      color: kWarningAmber,
                      title: 'Oversized',
                      count: oversized,
                      total: total,
                    ),
                    const SizedBox(height: 8),
                    _buildDonutLegendItem(
                      color: kDangerRed,
                      title: 'Overcapacity',
                      count: overcapacity,
                      total: total,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDonutLegendItem({
    required Color color,
    required String title,
    required int count,
    required int total,
  }) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '$count ($pct%)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFleetEfficiencyLeaderboard() {
    final sorted = List<Map<String, dynamic>>.from(_assignments.map((a) => Map<String, dynamic>.from(a as Map)));
    sorted.sort((a, b) => _num(b['score']).compareTo(_num(a['score'])));

    final topMatches = sorted.take(2).toList();
    final bottomMatches = sorted.reversed.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fleet Pairing Leaderboard',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 2),
          const Text(
            'Top optimized matches vs. assignments requiring monitoring',
            style: TextStyle(fontSize: 11, color: kTextSecondary),
          ),
          const SizedBox(height: 14),

          const Text(
            '🏆 TOP EFFICIENT MATCHES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: kSuccessGreen,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...topMatches.map((m) => _buildLeaderboardTile(m, isTop: true)),

          const SizedBox(height: 14),
          const Text(
            '⚠️ LOWEST MATCH SCORES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: kWarningAmber,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...bottomMatches.map((m) => _buildLeaderboardTile(m, isTop: false)),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTile(Map<String, dynamic> match, {required bool isTop}) {
    final busLabel = (match['bus'] as Map?)?['label']?.toString() ?? 'Bus';
    final routeLabel = (match['route'] as Map?)?['label']?.toString() ?? 'Route';
    final score = _num(match['score']);
    final cost = _num(match['diesel_cost']);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isTop ? kSuccessGreen.withOpacity(0.05) : kWarningAmber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isTop ? kSuccessGreen.withOpacity(0.2) : kWarningAmber.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isTop ? Icons.military_tech_rounded : Icons.info_outline_rounded,
            size: 18,
            color: isTop ? kSuccessGreen : kWarningAmber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$busLabel → $routeLabel',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '₹${cost.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11, color: kTextSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isTop ? kSuccessGreen : kWarningAmber,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(score * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── UTILITY DIALOGS & STATES ─────────────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kPrimaryBlue.withOpacity(0.15),
                  blurRadius: 16,
                )
              ],
            ),
            child: const CircularProgressIndicator(
              color: kSecondaryBlue,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Computing Optimal Fleet Assignments...',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Executing Hungarian Algorithm across cost, time & capacity',
            style: TextStyle(fontSize: 12, color: kTextSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: kDangerRed),
            const SizedBox(height: 12),
            const Text(
              'Optimization Service Unavailable',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: kSecondaryBlue),
            SizedBox(width: 8),
            Text('Hungarian Optimization'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This admin panel uses SciPy\'s Hungarian linear sum assignment algorithm to find globally optimal bus-to-route pairings.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Key Metrics Evaluated:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            SizedBox(height: 6),
            Text('• Diesel Cost: Fuel efficiency & route distance', style: TextStyle(fontSize: 12)),
            Text('• Travel Time: Distance & traffic index scaling', style: TextStyle(fontSize: 12)),
            Text('• Capacity Fit: Sharply penalizes seat shortages', style: TextStyle(fontSize: 12)),
            Text('• Bus Condition: Vehicle maintenance score', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
