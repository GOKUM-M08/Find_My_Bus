import 'package:flutter/material.dart';
import 'route_management_screen.dart';

/// Legacy screen consolidated into [RouteManagementScreen].
class RouteProfileScreen extends StatelessWidget {
  final String schoolId;
  final String schoolName;

  const RouteProfileScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  Widget build(BuildContext context) {
    return RouteManagementScreen(
      schoolId: schoolId,
      schoolName: schoolName,
    );
  }
}
