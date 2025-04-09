import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiKeys {
  static String get googleMapsApiKey => 
    dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
}
