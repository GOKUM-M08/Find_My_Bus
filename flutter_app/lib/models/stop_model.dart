// NOTE: listed in the guide's folder structure but never fleshed out —
// tracking_screen.dart reads stop data as raw Map<String, dynamic>
// straight from Supabase instead. Typed wrapper matching the `stops`
// table in database/schema.sql.

class StopModel {
  final String id;
  final String routeId;
  final String stopName;
  final double latitude;
  final double longitude;
  final int stopOrder;
  final String? expectedTime;

  StopModel({
    required this.id,
    required this.routeId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    required this.stopOrder,
    this.expectedTime,
  });

  factory StopModel.fromJson(Map<String, dynamic> json) {
    return StopModel(
      id: json['id'],
      routeId: json['route_id'],
      stopName: json['stop_name'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      stopOrder: json['stop_order'],
      expectedTime: json['expected_time'],
    );
  }
}
