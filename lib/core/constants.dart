import 'package:supabase_flutter/supabase_flutter.dart';

class AppConstants {
  static const String supabaseUrl = 'https://xyyvjidgwmluwsnhwzrn.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5eXZqaWRnd21sdXdzbmh3enJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI1MjAzODQsImV4cCI6MjA4ODA5NjM4NH0.cnJBCzLXQD-nbCXUlB5UHJEhJgn-s8qaL-RsdS3G4Pk';

  // Free API endpoints
  static const String nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  static const String bigDataCloudBaseUrl = 'https://api.bigdatacloud.net/data';
  static const String osrmBaseUrl = 'https://router.project-osrm.org';
  static const String overpassBaseUrl = 'https://overpass-api.de/api';
  static const String openMeteoBaseUrl = 'https://api.open-meteo.com/v1';
  static const String osmTileUrl = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
  static const String osmDarkTileUrl = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}'; // Google doesn't have a direct dark tile URL like this, falling back to standard

  // XP Values
  static const int xpNewVillage = 10;
  static const int xpNewCity = 25;
  static const int xpNewState = 50;
  static const int xpNewCountry = 200;
  static const int xpTravel50km = 20;
  static const int xpCompletePlan = 15;
  static const int xp7DayStreak = 30;
  static const int xpUploadPhoto = 5;
  static const int xpFirstGroupTrip = 40;

  // Level thresholds
  static const Map<int, int> levelThresholds = {
    1: 0,
    2: 100,
    3: 500,
    4: 1500,
    5: 5000,
    6: 15000,
  };

  static const Map<int, String> levelNames = {
    1: 'Traveler',
    2: 'Explorer',
    3: 'Adventurer',
    4: 'Roadmaster',
    5: 'Global Nomad',
    6: 'Legend',
  };

  static SupabaseClient get supabase => Supabase.instance.client;
}
