import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
class RouteOptimizerScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  const RouteOptimizerScreen({super.key, required this.schoolId, required this.schoolName});

  @override
  State<RouteOptimizerScreen> createState() => _RouteOptimizerScreenState();
}

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen> {
  double _cost = .4, _time = .3, _capacity = .2, _condition = .1;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.parse('$kBackendBaseUrl/admin/optimize-routes').replace(queryParameters: {
        'school_id': widget.schoolId,
        'w_cost': _cost.toStringAsFixed(2), 'w_time': _time.toStringAsFixed(2),
        'w_capacity': _capacity.toStringAsFixed(2), 'w_condition': _condition.toStringAsFixed(2),
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw Exception('Invalid response');
      if (mounted) setState(() => _data = body);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load recommendations. Check the backend URL and connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
  List<dynamic> get _assignments => (_data?['assignments'] as List?) ?? const [];
  List<dynamic> get _buses => (_data?['buses'] as List?) ?? const [];
  List<dynamic> get _routes => (_data?['routes'] as List?) ?? const [];
  List<dynamic> get _matrix => (_data?['matrix'] as List?) ?? const [];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Route Optimizer — ${widget.schoolName}'), actions: [
      IconButton(onPressed: _loading ? null : _fetch, icon: const Icon(Icons.refresh)),
    ]),
    body: _loading && _data == null ? const Center(child: CircularProgressIndicator())
      : _error != null && _data == null ? _errorState()
      : RefreshIndicator(onRefresh: _fetch, child: ListView(
        physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
          _summary(), const SizedBox(height: 16), _controls(), const SizedBox(height: 20),
          _heading('Suitability heatmap'), _heatmap(), const SizedBox(height: 20),
          _heading('Diesel cost by assigned bus'), _chart(), const SizedBox(height: 20),
          _heading('Recommended assignments'),
          if (_assignments.isEmpty) _empty() else ..._assignments.map((a) => _assignment(Map<String, dynamic>.from(a as Map))),
        ],
      )),
  );

  Widget _errorState() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_outlined, size: 50, color: Colors.red), const SizedBox(height: 12),
    Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton(onPressed: _fetch, child: const Text('Try again')),
  ])));

  Widget _summary() => Row(children: [
    _stat(Icons.local_gas_station_outlined, 'Total diesel cost', '₹${_num(_data?['total_diesel_cost']).toStringAsFixed(2)}'),
    const SizedBox(width: 12), _stat(Icons.co2_outlined, 'Total CO₂', '${_num(_data?['total_co2_kg']).toStringAsFixed(2)} kg'),
  ]);
  Widget _stat(IconData icon, String label, String value) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: const Color(0xFF1E6BFF)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  ]))));

  Widget _controls() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Optimization weights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    _slider('Diesel Cost', _cost, (v) => setState(() => _cost = v)),
    _slider('Travel Time', _time, (v) => setState(() => _time = v)),
    _slider('Capacity Fit', _capacity, (v) => setState(() => _capacity = v)),
    _slider('Bus Condition', _condition, (v) => setState(() => _condition = v)),
    Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _loading ? null : _fetch, icon: const Icon(Icons.auto_fix_high), label: const Text('Re-optimize'))),
  ])));
  Widget _slider(String name, double value, ValueChanged<double> update) => Column(children: [
    Row(children: [Text(name), const Spacer(), Text(value.toStringAsFixed(2))]), Slider(value: value, min: 0, max: 1, divisions: 20, onChanged: update),
  ]);
  Widget _heading(String title) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)));

  Widget _heatmap() {
    if (_buses.isEmpty || _routes.isEmpty) return _empty();
    return Card(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Table(
      defaultColumnWidth: const FixedColumnWidth(96), border: TableBorder.all(color: Colors.grey.shade300), children: [
        TableRow(children: [const Padding(padding: EdgeInsets.all(8), child: Text('Bus / Route', style: TextStyle(fontWeight: FontWeight.bold))), ..._routes.map((r) => _label((r as Map)['label']?.toString() ?? 'Route'))]),
        ...List.generate(_buses.length, (i) { final row = i < _matrix.length ? _matrix[i] as List : const []; return TableRow(children: [
          _label((_buses[i] as Map)['label']?.toString() ?? 'Bus'), ...List.generate(_routes.length, (j) { final score = j < row.length ? _num(row[j]) : 0.0; return Container(height: 48, alignment: Alignment.center, color: Color.lerp(Colors.red.shade100, Colors.green.shade700, score), child: Text(score.toStringAsFixed(2), style: TextStyle(color: score > .55 ? Colors.white : Colors.black87))); }),
        ]); }),
      ],
    )));
  }
  Widget _label(String text) => Padding(padding: const EdgeInsets.all(8), child: SizedBox(height: 32, child: Center(child: Text(text, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis))));

  Widget _chart() {
    if (_assignments.isEmpty) return _empty();
    final high = _assignments.map((a) => _num((a as Map)['diesel_cost'])).reduce((a, b) => a > b ? a : b);
    return SizedBox(height: 230, child: BarChart(BarChartData(maxY: high == 0 ? 1 : high * 1.2, borderData: FlBorderData(show: false), gridData: const FlGridData(drawVerticalLine: false), titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) { final i = v.toInt(); if (i < 0 || i >= _assignments.length) return const SizedBox.shrink(); final bus = ((_assignments[i] as Map)['bus'] as Map?)?['label']?.toString() ?? 'Bus'; return Padding(padding: const EdgeInsets.only(top: 6), child: Text(bus, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)); })),
    ), barGroups: List.generate(_assignments.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: _num((_assignments[i] as Map)['diesel_cost']), color: const Color(0xFF1E6BFF), width: 20, borderRadius: BorderRadius.circular(4))])))));
  }

  Widget _assignment(Map<String, dynamic> a) {
    final warning = a['capacity_fit'] == 'Overcapacity'; final bus = (a['bus'] as Map?)?['label']?.toString() ?? 'Bus'; final route = (a['route'] as Map?)?['label']?.toString() ?? 'Route';
    return Card(color: warning ? Colors.red.shade50 : null, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(warning ? Icons.warning_amber_rounded : Icons.directions_bus, color: warning ? Colors.red : const Color(0xFF1E6BFF)), const SizedBox(width: 8), Expanded(child: Text('$bus → $route', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))]), const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, children: [Text('Score ${_num(a['score']).toStringAsFixed(2)}'), Text('₹${_num(a['diesel_cost']).toStringAsFixed(2)}'), Text('${_num(a['travel_time_hours']).toStringAsFixed(2)} h'), Text('${_num(a['co2_kg']).toStringAsFixed(2)} kg CO₂')]), const SizedBox(height: 6),
      Text('Capacity: ${a['capacity_fit']}', style: TextStyle(color: warning ? Colors.red.shade800 : Colors.black87, fontWeight: warning ? FontWeight.bold : FontWeight.normal)), Text(a['explanation']?.toString() ?? ''),
    ])));
  }
  Widget _empty() => const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No buses and routes are available to optimize yet.')));
}
