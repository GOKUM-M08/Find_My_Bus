// NOTE: listed in the guide's folder structure but never fleshed out —
// every screen in the guide calls `Supabase.instance.client` directly
// (see login_screen.dart, tracking_screen.dart, driver_screen.dart,
// home_screen.dart). This thin wrapper is provided as a starting
// point if you'd rather centralize Supabase calls behind one service.

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://yourproject.supabase.co',
      anonKey: 'your_anon_key',
    );
  }

  static Future<Map<String, dynamic>?> getLiveLocation(String busId) async {
    final response = await client
        .from('live_location')
        .select()
        .eq('bus_id', busId)
        .maybeSingle();
    return response;
  }

  static Future<List<Map<String, dynamic>>> getRouteStops(String busId) async {
    final routes = await client
        .from('routes')
        .select('*, stops(*)')
        .eq('bus_id', busId)
        .maybeSingle();
    if (routes == null || routes['stops'] == null) return [];
    return List<Map<String, dynamic>>.from(routes['stops']);
  }
}
