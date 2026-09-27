import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/admin_drawer.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

class RegisterStudentScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const RegisterStudentScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<RegisterStudentScreen> createState() => _RegisterStudentScreenState();
}

class _RegisterStudentScreenState extends State<RegisterStudentScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _buses = [];
  Map<String, List<Map<String, dynamic>>> _stopsByBus = {};

  bool _loading = true;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final studentRows = await supabase
          .from('students')
          .select('*, buses(bus_number), stops(stop_name)')
          .eq('school_id', widget.schoolId)
          .order('student_name');

      final busRows = await supabase
          .from('buses')
          .select('id, bus_number')
          .eq('school_id', widget.schoolId);

      final routeRows = await supabase
          .from('routes')
          .select('id, bus_id, stops(*)')
          .eq('school_id', widget.schoolId);

      final Map<String, List<Map<String, dynamic>>> stopsMap = {};
      for (final r in routeRows) {
        final bId = r['bus_id'];
        if (bId != null && r['stops'] != null) {
          final stops = List<Map<String, dynamic>>.from(r['stops']);
          stops.sort((a, b) => (a['stop_order'] as int? ?? 0).compareTo(b['stop_order'] as int? ?? 0));
          stopsMap[bId as String] = stops;
        }
      }

      if (!mounted) return;
      setState(() {
        _students = List<Map<String, dynamic>>.from(studentRows);
        _buses = List<Map<String, dynamic>>.from(busRows);
        _stopsByBus = stopsMap;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load student data: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _logAudit(String actionType, String targetId, String details) async {
    try {
      final user = supabase.auth.currentUser;
      await supabase.from('admin_audit_logs').insert({
        'school_id': widget.schoolId,
        'admin_user_id': user?.id,
        'admin_email': user?.email,
        'action_type': actionType,
        'target_entity': 'students',
        'target_id': targetId,
        'details': details,
      });
    } catch (_) {}
  }

  void _showAddEditStudentModal([Map<String, dynamic>? existingStudent]) {
    final formKey = GlobalKey<FormState>();
    final isEdit = existingStudent != null;

    final nameCtrl = TextEditingController(text: existingStudent?['student_name'] ?? '');
    final parentNameCtrl = TextEditingController(text: existingStudent?['parent_name'] ?? '');
    final parentPhoneCtrl = TextEditingController(text: existingStudent?['parent_phone'] ?? '');
    final parentEmailCtrl = TextEditingController(text: existingStudent?['parent_email'] ?? '');

    String? selectedBusId = existingStudent?['bus_id'];
    String? selectedStopId = existingStudent?['stop_id'];

    bool saving = false;
    String? modalError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final availableStops = selectedBusId != null ? (_stopsByBus[selectedBusId] ?? []) : <Map<String, dynamic>>[];

          return AlertDialog(
            title: Text(isEdit ? 'Edit Student Details' : 'Register New Student'),
            content: SingleChildScrollView(
              child: Container(
                width: 420,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (modalError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          color: Colors.red.shade50,
                          child: Text(modalError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Student Full Name *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Student name is required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: parentNameCtrl,
                        decoration: const InputDecoration(labelText: 'Parent / Guardian Name'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: parentPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Parent Contact Phone Number'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: parentEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Parent Email Address'),
                        validator: (v) {
                          if (v != null && v.isNotEmpty && (!v.contains('@') || !v.contains('.'))) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedBusId,
                        decoration: const InputDecoration(labelText: 'Assigned Bus Vehicle'),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('No Bus Assigned')),
                          ..._buses.map((b) => DropdownMenuItem<String>(
                                value: b['id'] as String,
                                child: Text('Bus ${b['bus_number']}'),
                              )),
                        ],
                        onChanged: (val) {
                          setModalState(() {
                            selectedBusId = val;
                            selectedStopId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedStopId,
                        decoration: const InputDecoration(labelText: 'Assigned Pickup/Drop Stop'),
                        disabledHint: const Text('Select a bus first'),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('No Stop Assigned')),
                          ...availableStops.map((s) => DropdownMenuItem<String>(
                                value: s['id'] as String,
                                child: Text('Stop ${s['stop_order']}: ${s['stop_name']}'),
                              )),
                        ],
                        onChanged: (val) => setModalState(() => selectedStopId = val),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });

                        final payload = {
                          'school_id': widget.schoolId,
                          'student_name': nameCtrl.text.trim(),
                          'parent_name': parentNameCtrl.text.trim(),
                          'parent_phone': parentPhoneCtrl.text.trim(),
                          'parent_email': parentEmailCtrl.text.trim(),
                          'bus_id': selectedBusId,
                          'stop_id': selectedStopId,
                        };

                        try {
                          if (isEdit) {
                            await supabase.from('students').update(payload).eq('id', existingStudent['id']);
                            await _logAudit('UPDATE_STUDENT', existingStudent['id'], 'Updated student ${nameCtrl.text.trim()}');
                          } else {
                            final res = await supabase.from('students').insert(payload).select();
                            final newId = (res as List).isNotEmpty ? res[0]['id'] : '';
                            await _logAudit('CREATE_STUDENT', newId.toString(), 'Registered student ${nameCtrl.text.trim()}');
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            _fetchData();
                          }
                        } catch (e) {
                          setModalState(() {
                            saving = false;
                            modalError = 'Failed to save student: ${e.toString()}';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Save Changes' : 'Register Student'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteStudent(Map<String, dynamic> student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Student Deletion'),
        content: Text('Are you sure you want to delete student "${student['student_name']}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Student'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('students').delete().eq('id', student['id']);
        await _logAudit('DELETE_STUDENT', student['id'], 'Deleted student ${student['student_name']}');
        _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Student "${student['student_name']}" deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete student: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final filteredStudents = _students.where((s) {
      final name = s['student_name'].toString().toLowerCase();
      final parent = (s['parent_name'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || parent.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: AdminDrawer(
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        currentRoute: 'students',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Student Transport List'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Register Student',
            onPressed: () => _showAddEditStudentModal(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchData(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Student Roster', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
                            onPressed: () => _showAddEditStudentModal(),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Register Student'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search by student or parent name...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                      const SizedBox(height: 16),
                      filteredStudents.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No students found.')))
                          : isDesktop
                              ? _buildDesktopTable(filteredStudents)
                              : _buildMobileCards(filteredStudents),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> students) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Student Name')),
          DataColumn(label: Text('Parent Name')),
          DataColumn(label: Text('Parent Phone')),
          DataColumn(label: Text('Assigned Bus')),
          DataColumn(label: Text('Assigned Stop')),
          DataColumn(label: Text('Actions')),
        ],
        rows: students.map((s) {
          final busName = (s['buses'] != null && s['buses']['bus_number'] != null) ? s['buses']['bus_number'] : 'Unassigned';
          final stopName = (s['stops'] != null && s['stops']['stop_name'] != null) ? s['stops']['stop_name'] : 'Unassigned';

          return DataRow(cells: [
            DataCell(Text(s['student_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(s['parent_name'] ?? '—')),
            DataCell(Text(s['parent_phone'] ?? '—')),
            DataCell(Text(busName.toString())),
            DataCell(Text(stopName.toString())),
            DataCell(Row(
              children: [
                IconButton(icon: const Icon(Icons.edit, color: kPrimaryBlue), onPressed: () => _showAddEditStudentModal(s)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteStudent(s)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildMobileCards(List<Map<String, dynamic>> students) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final s = students[idx];
        final busName = (s['buses'] != null && s['buses']['bus_number'] != null) ? s['buses']['bus_number'] : 'Unassigned';
        final stopName = (s['stops'] != null && s['stops']['stop_name'] != null) ? s['stops']['stop_name'] : 'Unassigned';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s['student_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: kPrimaryBlue), onPressed: () => _showAddEditStudentModal(s)),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteStudent(s)),
                    ],
                  )
                ],
              ),
              Text('Parent: ${s['parent_name'] ?? '—'} (${s['parent_phone'] ?? '—'})'),
              Text('Bus: $busName  |  Stop: $stopName'),
            ],
          ),
        );
      },
    );
  }
}