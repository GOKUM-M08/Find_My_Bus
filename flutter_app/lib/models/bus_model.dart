// NOTE: listed in the guide's folder structure but never fleshed out —
// every screen in the guide (tracking_screen.dart, home_screen.dart,
// driver_screen.dart) reads bus data as raw Map<String, dynamic>
// straight from Supabase instead of a typed model. This is a simple
// typed wrapper matching the `buses` table in database/schema.sql,
// provided as a starting point if you want to move to typed models.

class BusModel {
  final String id;
  final String schoolId;
  final String busNumber;
  final String? busCode;
  final String? driverName;
  final String? driverPhone;
  final String? deviceId;
  final int capacity;
  final bool isActive;

  BusModel({
    required this.id,
    required this.schoolId,
    required this.busNumber,
    this.busCode,
    this.driverName,
    this.driverPhone,
    this.deviceId,
    this.capacity = 40,
    this.isActive = true,
  });

  factory BusModel.fromJson(Map<String, dynamic> json) {
    return BusModel(
      id: json['id'],
      schoolId: json['school_id'],
      busNumber: json['bus_number'],
      busCode: json['bus_code'],
      driverName: json['driver_name'],
      driverPhone: json['driver_phone'],
      deviceId: json['device_id'],
      capacity: json['capacity'] ?? 40,
      isActive: json['is_active'] ?? true,
    );
  }
}
