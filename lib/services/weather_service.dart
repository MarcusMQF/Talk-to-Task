import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api_keys.dart';

class WeatherService {
  // Weather conditions and their corresponding emojis
  static const Map<String, String> weatherEmojis = {
    'Clear': '☀️',
    'Clouds': '☁️',
    'Rain': '🌧️',
    'Drizzle': '🌦️',
    'Thunderstorm': '⛈️',
    'Snow': '❄️',
    'Mist': '🌫️',
    'Smoke': '🌫️',
    'Haze': '🌫️',
    'Dust': '🌫️',
    'Fog': '🌫️',
    'Sand': '🌫️',
    'Ash': '🌫️',
    'Squall': '💨',
    'Tornado': '🌪️',
  };

  // Base URL for OpenWeather API
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';
  
  /// Fetches current weather for the given coordinates
  Future<Map<String, dynamic>> getWeatherByLocation(double lat, double lon) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?lat=$lat&lon=$lon&appid=${ApiKeys.openWeatherApiKey}&units=metric')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final weatherData = {
          'main': data['weather'][0]['main'],
          'description': data['weather'][0]['description'],
          'temperature': data['main']['temp'],
          'humidity': data['main']['humidity'],
          'windSpeed': data['wind']['speed'],
          'emoji': weatherEmojis[data['weather'][0]['main']] ?? '🌈',
        };
        return weatherData;
      } else {
        throw Exception('Failed to load weather data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching weather data: $e');
    }
  }
} 