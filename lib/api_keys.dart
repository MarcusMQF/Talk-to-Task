import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiKeys {
  static String get googleMapsApiKey => 
    dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    
  static String get geminiApiKey =>
    dotenv.env['GEMINI_API_KEY'] ?? '';
    
  static String get openWeatherApiKey =>
    dotenv.env['OPEN_WEATHER_API_KEY'] ?? '';
}
