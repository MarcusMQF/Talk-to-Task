import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:flutter/foundation.dart';
import './weather_service.dart'; // Import the real weather service


class DeviceInfoService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final Location _location = Location();
  final WeatherService _weatherService = WeatherService(); // Add real weather service
  LocationData? _currentPosition;
  // Cache for weather data
  Map<String, String> _weatherCache = {};
  String _country = "Unknown";
  Future<bool> initializeLocation() async {
    try {
      // Check if location service is enabled
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          print("Location services are disabled");
          return false;
        }
      }

      // Check for location permission
      PermissionStatus permissionStatus = await _location.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await _location.requestPermission();
        if (permissionStatus != PermissionStatus.granted) {
          print("Location permission denied");
          return false;
        }
      }

      // Configure location settings
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 10000, // 10 seconds
        distanceFilter: 10, // 10 meters
      );

      // Get initial location
      _currentPosition = await _location.getLocation();

      // Get country from coordinates
      if (_currentPosition != null &&
          _currentPosition!.latitude != null &&
          _currentPosition!.longitude != null) {
        _country = await _getCountryFromCoordinates(
            _currentPosition!.latitude!, _currentPosition!.longitude!);
      }

      print("Location initialized: $_country");
      return true;
    } catch (e) {
      print("Error initializing location: $e");
      return false;
    }
  }

  // Get country from coordinates using reverse geocoding
  Future<String> _getCountryFromCoordinates(
      double latitude, double longitude) async {
    try {
      if (latitude == 0.0 && longitude == 0.0) {
        return "Malaysia"; // Default for your app's context
      }

      print('Getting country from coordinates: $latitude, $longitude');

      List<geo.Placemark> placemarks =
          await geo.placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty &&
          placemarks.first.country != null &&
          placemarks.first.country!.isNotEmpty) {
        print('Found country: ${placemarks.first.country}');
        return placemarks.first.country!;
      }

      return "Malaysia"; // Default fallback
    } catch (e) {
      print("Error getting country from coordinates: $e");
      return "Malaysia"; // Default fallback
    }
  }

  Future<Map<String, dynamic>> getDeviceContext() async {
    // Get battery level
    final batteryLevel = await _battery.batteryLevel;

    // Get battery charging state
    final batteryState = await _battery.batteryState;
    final isCharging = batteryState == BatteryState.charging ||
        batteryState == BatteryState.full;

    // Get network status
    final connectivityResult = await _connectivity.checkConnectivity();
    final networkStatus = _getNetworkStrength(connectivityResult);

    // Get current time
    final now = DateTime.now();
    final timeStr = DateFormat('h:mm a').format(now);

    // Get traffic condition based on time
    final trafficCondition = _getTrafficCondition(now);

    // Get real weather data
    final weather = await _getWeatherData();

    return {
      'battery': '$batteryLevel%${isCharging ? " (Charging)" : ""}',
      'network': networkStatus,
      'time': '$timeStr, $trafficCondition traffic',
      'weather': weather,
    };
  }

  Future<String> _getWeatherData() async {
    try {
      // Check if we have cached weather within the last 15 minutes
      final now = DateTime.now();
      final dateKey = '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute ~/ 15}';

      if (_weatherCache.containsKey(dateKey)) {
        debugPrint('Using cached weather data');
        return _weatherCache[dateKey]!;
      }

      // Make sure we have location data
      if (_currentPosition == null || 
          _currentPosition!.latitude == null || 
          _currentPosition!.longitude == null) {
        debugPrint('Location data not available for weather');
        return "Weather unavailable";
      }
      
      // Use the real WeatherService to get actual weather data
      final weatherData = await _weatherService.getWeatherByLocation(
        _currentPosition!.latitude!,
        _currentPosition!.longitude!
      );
      
      // Format the weather data
      final formattedWeather = "${weatherData['main']}, ${weatherData['temperature'].toStringAsFixed(1)}°C";
      debugPrint('Got real weather data: $formattedWeather');
      
      // Cache the result for 15 minutes
      _weatherCache[dateKey] = formattedWeather;
      
      return formattedWeather;
    } catch (e) {
      debugPrint('Error fetching real weather data: $e');
      return "Weather unavailable";
    }
  }

  String _getNetworkStrength(ConnectivityResult result) {
    // Existing method implementation
    switch (result) {
      case ConnectivityResult.mobile:
        return 'Strong (4G)';
      case ConnectivityResult.wifi:
        return 'Strong (WiFi)';
      case ConnectivityResult.none:
        return 'No Connection';
      default:
        return 'Unknown';
    }
  }

  String _getTrafficCondition(DateTime time) {
    // Existing method implementation
    final hour = time.hour;
    if ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19)) {
      return 'heavy';
    } else if ((hour >= 10 && hour <= 16) || (hour >= 20 && hour <= 22)) {
      return 'moderate';
    } else {
      return 'light';
    }
  }
}
