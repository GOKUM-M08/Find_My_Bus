import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'config.dart';
import '../widgets/admin_drawer.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

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

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen> {
  double _cost = 0.35;
  double _time = 0.25;
  double _capacity = 0.20;
  double _condition = 0.10;
  double _compatibility = 0.10;

  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  Future<void> _fetchRecommendations() async {
    final totalWeight = _cost + _time + _capacity + _condition + _compatibility;
    if (totalWeight <= 0) {
      setState(() {
        _error = 'Please select at least one positive optimization weight.';
        _loading = false;
      });
      return;
    }

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
          'w_compatibility': _compatibility.toStringAsFixed(2),
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw Exception('Invalid data structure from optimizer backend');
      }

      if (!mounted) return;
      setState(() {
        _data = body;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not fetch optimization recommendations from backend ($kBackendBaseUrl).\nVerify backend service is running.';
        _loading = false;
      });
    }
  }

  void _applyPreset(double c, double t, double cap, double cond, double comp) {
    setState(() {
      _cost = c;
      _time = t;
      _capacity = cap;
      _condition = cond;
      _compatibility = comp;
    });
    _fetchRecommendations();
  }

  @override
  Widget build(BuildContext context) {
    final assignments = (_data?['assignments'] as List?) ?? [];
    final comp = _data?['comparison'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: AdminDrawer(
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        currentRoute: 'optimizer',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Hungarian Route Optimizer'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRecommendations,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : _error != null
              ? _buildErrorState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPresetBar(),
                      const SizedBox(height: 16),
                      _buildWeightSliders(),
                      const SizedBox(height: 20),
                      if (comp != null) ...[
                        _buildComparisonHeader(comp),
                        const SizedBox(height: 20),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Optimized Bus-to-Route Recommendations',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text('${assignments.length} Optimal Pairings', style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      assignments.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No buses/routes available for optimization.')))
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: assignments.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, idx) => _buildAssignmentCard(assignments[idx]),
                            ),
                    ],
                  ),
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
            const Icon(Icons.error_outline, color: Colors.red, size: 54),
            const SizedBox(height: 12),
            const Text('Optimizer Error', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchRecommendations,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Optimization'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text('Presets: ', style: TextStyle(fontWeight: FontWeight.bold)),
          ActionChip(label: const Text('Balanced'), onPressed: () => _applyPreset(0.35, 0.25, 0.20, 0.10, 0.10)),
          const SizedBox(width: 8),
          ActionChip(label: const Text('Cost Saver'), onPressed: () => _applyPreset(0.60, 0.10, 0.15, 0.05, 0.10)),
          const SizedBox(width: 8),
          ActionChip(label: const Text('Fastest Commute'), onPressed: () => _applyPreset(0.15, 0.60, 0.10, 0.05, 0.10)),
          const SizedBox(width: 8),
          ActionChip(label: const Text('Capacity Fit'), onPressed: () => _applyPreset(0.15, 0.15, 0.50, 0.10, 0.10)),
        ],
      ),
    );
  }

  Widget _buildWeightSliders() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Algorithm Scoring Weights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _sliderRow('Fuel Cost Weight', _cost, (v) => setState(() => _cost = v)),
          _sliderRow('Commute Time Weight', _time, (v) => setState(() => _time = v)),
          _sliderRow('Student Capacity Weight', _capacity, (v) => setState(() => _capacity = v)),
          _sliderRow('Vehicle Condition Weight', _condition, (v) => setState(() => _condition = v)),
          _sliderRow('Route Compatibility Weight', _compatibility, (v) => setState(() => _compatibility = v)),
          const SizedBox(height: 14),
          const Text('Weight Distribution Visualizer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          _buildWeightPieChart(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
              onPressed: _fetchRecommendations,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Re-Run Hungarian Engine'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightPieChart() {
    final total = _cost + _time + _capacity + _condition + _compatibility;
    if (total <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: 140,
      child: PieChart(
        PieChartData(
          sectionsSpace: 3,
          centerSpaceRadius: 28,
          sections: [
            PieChartSectionData(value: _cost, color: Colors.blue, title: 'Cost\n${((_cost / total) * 100).toStringAsFixed(0)}%', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            PieChartSectionData(value: _time, color: Colors.orange, title: 'Time\n${((_time / total) * 100).toStringAsFixed(0)}%', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            PieChartSectionData(value: _capacity, color: Colors.purple, title: 'Cap\n${((_capacity / total) * 100).toStringAsFixed(0)}%', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            PieChartSectionData(value: _condition, color: Colors.teal, title: 'Cond\n${((_condition / total) * 100).toStringAsFixed(0)}%', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            PieChartSectionData(value: _compatibility, color: Colors.indigo, title: 'Comp\n${((_compatibility / total) * 100).toStringAsFixed(0)}%', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double val, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 180, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: val,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: val.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 45, child: Text(val.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildComparisonHeader(Map<String, dynamic> comp) {
    final beforeCost = (comp['before']?['diesel_cost'] as num?)?.toDouble() ?? 0.0;
    final afterCost = (comp['after']?['diesel_cost'] as num?)?.toDouble() ?? 0.0;
    final costSavingsPct = (comp['improvement']?['cost_savings_pct'] as num?)?.toDouble() ?? 0.0;
    final monthlySavings = (beforeCost - afterCost) * 22;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Optimization Savings Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                    Text(
                      'Baseline: ₹${beforeCost.toStringAsFixed(0)}/day  ➔  Optimized: ₹${afterCost.toStringAsFixed(0)}/day '
                      '(${costSavingsPct.toStringAsFixed(1)}% reduction)',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF14532D)),
                    ),
                    if (monthlySavings > 0)
                      Text(
                        'Est. Monthly Savings: ₹${monthlySavings.toStringAsFixed(0)} (22 operating days)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildCostBarChart(beforeCost, afterCost),
        ],
      ),
    );
  }

  Widget _buildCostBarChart(double beforeCost, double afterCost) {
    final maxY = (beforeCost > 0 ? beforeCost : 100.0) * 1.25;
    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  switch (value.toInt()) {
                    case 0:
                      return const Text('Baseline Cost', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red));
                    case 1:
                      return const Text('AI Optimized', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green));
                    default:
                      return const Text('');
                  }
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            BarChartGroupData(
              x: 0,
              barRods: [
                BarChartRodData(
                  toY: beforeCost,
                  color: Colors.red.shade400,
                  width: 36,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
            BarChartGroupData(
              x: 1,
              barRods: [
                BarChartRodData(
                  toY: afterCost,
                  color: Colors.green.shade600,
                  width: 36,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(dynamic assignment) {
    final map = Map<String, dynamic>.from(assignment as Map);
    final busLabel = map['bus']?['label'] ?? 'Bus';
    final routeLabel = map['route']?['label'] ?? 'Route';
    final score = (map['score'] as num?)?.toDouble() ?? 0.0;
    final cost = (map['diesel_cost'] as num?)?.toDouble() ?? 0.0;
    final explanation = map['explanation'] ?? '';
    final fitLabel = map['capacity_fit'] ?? '';

    final isEligible = map['eligible'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isEligible ? Colors.grey.shade300 : Colors.red.shade300, width: isEligible ? 1 : 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$busLabel ➔ $routeLabel', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isEligible ? Colors.blue.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Match Score: ${(score * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isEligible ? kPrimaryBlue : Colors.red, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Capacity Fit: $fitLabel  |  Est. Diesel Cost: ₹${cost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Plain-English Recommendation:\n$explanation',
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }
}
