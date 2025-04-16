import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:geocoding/geocoding.dart' as geo;

import 'dart:math';

class DeviceInfoService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final Location _location = Location();
  LocationData? _currentPosition;
  // Mock weather data - replace with actual API call in production
  Map<String, String> _weatherCache = {};
  final List<String> _weatherConditions = [
    'Sunny',
    'Partly cloudy',
    'Cloudy',
    'Light rain',
    'Raining',
    'Thunderstorms'
  ];
  final List<String> _temperatures = [
    '28°C',
    '29°C',
    '30°C',
    '31°C',
    '32°C',
    '27°C'
  ];
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

    // Get weather data
    final weather = await _getWeatherData();

    return {
      'battery': '$batteryLevel%${isCharging ? " (Charging)" : ""}',
      'network': networkStatus,
      'time': '$timeStr, $trafficCondition traffic',
      'weather': weather,
    };
  }

  Future<String> _getWeatherData() async {
    // In a real app, you would call a weather API here
    // For now, we'll use mock data that changes based on time of day

    // Check if we have cached weather within the last hour
    final now = DateTime.now();
    final dateKey = '${now.year}-${now.month}-${now.day}-${now.hour}';

    if (_weatherCache.containsKey(dateKey)) {
      return _weatherCache[dateKey]!;
    }

    // Generate weather based on time of day
    final random = Random();
    int index;

    if (now.hour >= 6 && now.hour < 11) {
      // Morning - more likely to be clear
      index = random.nextInt(3); // First 3 conditions
    } else if (now.hour >= 11 && now.hour < 15) {
      // Midday - could be anything
      index = random.nextInt(_weatherConditions.length);
    } else if (now.hour >= 15 && now.hour < 19) {
      // Afternoon - more likely to rain
      index = 2 + random.nextInt(4); // Last 4 conditions
    } else {
      // Evening/night
      index = random.nextInt(_weatherConditions.length);
    }

    final tempIndex = random.nextInt(_temperatures.length);
    final weather = "${_weatherConditions[index]}, ${_temperatures[tempIndex]}";

    // Cache the result
    _weatherCache[dateKey] = weather;

    return weather;
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
