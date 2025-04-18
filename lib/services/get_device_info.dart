import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import './weather_service.dart';

class DeviceInfoService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final loc.Location _location = loc.Location(); // Use loc. prefix
  final WeatherService _weatherService = WeatherService();
  loc.LocationData? _currentPosition; // Use loc. prefix
  Map<String, String> _weatherCache = {};
  String _country = "Unknown";
  bool _hasInitialized = false;
  DateTime? _lastLocationUpdate;
  static const Duration LOCATION_CACHE_DURATION = Duration(minutes: 5);
  bool _isInitializingLocation = false;
  DateTime? _lastInitializationAttempt;
  static const Duration MIN_INITIALIZATION_INTERVAL = Duration(seconds: 10);
 bool _locationNeededForRequest = false;
 
  Future<bool> initialize() async {
    if (_hasInitialized) return true;

    // Prevent multiple simultaneous initialization attempts
    if (_isInitializingLocation) {
      print("🚫 Location initialization already in progress, skipping");
      return false;
    }

    // Prevent too frequent initialization attempts
    if (_lastInitializationAttempt != null) {
      final timeSinceLastAttempt =
          DateTime.now().difference(_lastInitializationAttempt!);
      if (timeSinceLastAttempt < MIN_INITIALIZATION_INTERVAL) {
        print("🚫 Location was initialized recently, waiting");
        return false;
      }
    }

    _isInitializingLocation = true;
    _lastInitializationAttempt = DateTime.now();

    try {
      bool success = await initializeLocation();
      _hasInitialized = success;
      return success;
    } finally {
      _isInitializingLocation = false;
    }
  }

  Future<bool> initializeLocation() async {
    try {
      await _location.changeSettings(
        accuracy:
            loc.LocationAccuracy.low, // Use lower accuracy for better speed
        interval: 60000, // 1 minute minimum between updates
        distanceFilter: 500, // Only update if moved 500 meters
      );

      if (_currentPosition != null) {
        print(
            "✅ Location previously available, skipping service/permission checks");
        // Just update the _country value
        if (_currentPosition!.latitude != null &&
            _currentPosition!.longitude != null) {
          _country = await _getCountryFromCoordinates(
              _currentPosition!.latitude!, _currentPosition!.longitude!);
          print("Country determined: $_country");
        }
        return true;
      }

      if (_currentPosition != null && _lastLocationUpdate != null) {
        final timeSinceLastUpdate =
            DateTime.now().difference(_lastLocationUpdate!);
        if (timeSinceLastUpdate < LOCATION_CACHE_DURATION) {
          print(
              "🕒 Using cached location (${timeSinceLastUpdate.inSeconds}s old)");
          return true;
        }
      }

      print("\n==== 🌍 LOCATION DEBUGGING ====");
      print("Starting location initialization...");

      bool serviceEnabled = await _location.serviceEnabled();
      print("Location services enabled: $serviceEnabled");

      if (!serviceEnabled) {
        print("Requesting location services...");
        serviceEnabled = await _location.requestService();
        print("Location services after request: $serviceEnabled");
      }

      loc.PermissionStatus permissionStatus = await _location.hasPermission();
      print("Current permission status: $permissionStatus");

      if (permissionStatus == loc.PermissionStatus.denied) {
        print("Requesting location permission...");
        permissionStatus = await _location.requestPermission();
        print("Permission status after request: $permissionStatus");
      }

      if (permissionStatus != loc.PermissionStatus.granted) {
        print("❌ Failed to get location permission");
        return false;
      }

      print("Getting current location...");
      _currentPosition = await _location.getLocation();
      print(
          "Location data: lat=${_currentPosition?.latitude}, lon=${_currentPosition?.longitude}");

      if (_currentPosition != null &&
          _currentPosition!.latitude != null &&
          _currentPosition!.longitude != null) {
        print("Reverse geocoding coordinates...");
        _country = await _getCountryFromCoordinates(
            _currentPosition!.latitude!, _currentPosition!.longitude!);
        print("Country determined: $_country");
      } else {
        print("❌ Invalid location data received");
      }

      print("Location initialization complete");
      print("==============================\n");
      return true;
    } catch (e) {
      print("❌ Error in location initialization: $e");
      return false;
    }
  }

  Future<String> _getCountryFromCoordinates(
      double latitude, double longitude) async {
    try {
      if (latitude == 0.0 && longitude == 0.0) {
        return "Malaysia"; // Default for your app's context
      }

      print('🔍 Getting country from coordinates: $latitude, $longitude');

      List<Placemark> placemarks =
          await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isNotEmpty &&
          placemarks.first.country != null &&
          placemarks.first.country!.isNotEmpty) {
        print('🏳️ Found country: ${placemarks.first.country}');
        return placemarks.first.country!;
      }

      return "Malaysia"; // Default fallback
    } catch (e) {
      print("⚠️ Error getting country from coordinates: $e");
      return "Malaysia"; // Default fallback
    }
  }

Future<Map<String, dynamic>> getDeviceContext({bool needLocation = false}) async {
    Map<String, dynamic> context = {};
    _locationNeededForRequest = needLocation;
    
    // ALWAYS use Malaysia as default country unless explicitly requested
    context['location'] = "Malaysia";
    
    // Only attempt to get real location if explicitly requested
    if (needLocation && _currentPosition != null) {
      try {
        // Use cached location data if available
        if (_country != "Unknown") {
          context['location'] = _country;
        } else if (_currentPosition!.latitude != null && _currentPosition!.longitude != null) {
          // We have coordinates but no country - get country name
          _country = await _getCountryFromCoordinates(
              _currentPosition!.latitude!, _currentPosition!.longitude!);
          context['location'] = _country;
        }
      } catch (e) {
        print('⚠️ Error with location data: $e');
        // Keep the default "Malaysia"
      }
    }

    // Rest of your method to get non-location device context
    final batteryLevel = await _battery.batteryLevel;
    final batteryState = await _battery.batteryState;
    final isCharging = batteryState == BatteryState.charging || 
                      batteryState == BatteryState.full;
    final connectivityResult = await _connectivity.checkConnectivity();
    final networkStatus = _getNetworkStrength(connectivityResult);
    final now = DateTime.now();
    final timeStr = DateFormat('h:mm a').format(now);
    final trafficCondition = _getTrafficCondition(now);
    
    // Use hardcoded weather for non-map contexts
    final weather = needLocation ? await _getWeatherData() : "Sunny, 28°C"; 

    context['battery'] = '$batteryLevel%${isCharging ? " (Charging)" : ""}';
    context['network'] = networkStatus;
    context['time'] = '$timeStr, $trafficCondition traffic';
    context['weather'] = weather;

    print("📱 Device context: $context");
    return context;
  }

  Future<String> _getWeatherData() async {
    try {
      // Check if we have cached weather within the last 15 minutes
      final now = DateTime.now();
      final dateKey =
          '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute ~/ 15}';

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
          _currentPosition!.latitude!, _currentPosition!.longitude!);

      // Format the weather data
      final formattedWeather =
          "${weatherData['main']}, ${weatherData['temperature'].toStringAsFixed(1)}°C";
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
