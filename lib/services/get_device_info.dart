import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoding/geocoding.dart';
import './weather_service.dart';
import 'dart:async';

typedef WeatherUpdateCallback = void Function(Map<String, dynamic> weatherData);

class DeviceInfoService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final loc.Location _location = loc.Location();
  final WeatherService _weatherService = WeatherService();

  // Location-related fields
  loc.LocationData? _currentPosition;
  String _country = "Unknown";
  bool _hasInitialized = false;
  DateTime? _lastLocationUpdate;
  bool _isInitializingLocation = false;
  DateTime? _lastInitializationAttempt;
  bool _locationNeededForRequest = false;
  bool _isAsyncInitializing = false;
  // Weather-related fields
  bool _isLoadingWeather = false;
  Map<String, dynamic>? _weatherData;

  // Constants
  static const Duration LOCATION_CACHE_DURATION = Duration(minutes: 5);
  static const Duration MIN_INITIALIZATION_INTERVAL = Duration(seconds: 10);

  // Callbacks - notice these are AFTER the typedef
  WeatherUpdateCallback? onWeatherUpdated;

  Future<bool> initialize() async {
    // Return true immediately if already initialized
    if (_hasInitialized) return true;

    // Prevent multiple simultaneous initialization attempts
    if (_isInitializingLocation || _isAsyncInitializing) {
      print("🚫 Location initialization already in progress");
      return false;
    }

    // Track that we're starting async initialization
    _isAsyncInitializing = true;

    // Start location initialization in the background
    _initializeLocationAsync();

    // Return immediately with success
    return true;
  }

// New method to handle async initialization
  void _initializeLocationAsync() {
    // Prevent too frequent initialization attempts
    if (_lastInitializationAttempt != null) {
      final timeSinceLastAttempt =
          DateTime.now().difference(_lastInitializationAttempt!);
      if (timeSinceLastAttempt < MIN_INITIALIZATION_INTERVAL) {
        print("🚫 Location was initialized recently, waiting");
        _isAsyncInitializing = false;
        return;
      }
    }

    _lastInitializationAttempt = DateTime.now();

    // Launch initialization in the background
    initializeLocation().then((success) {
      _hasInitialized = success;
      _isAsyncInitializing = false;
      print("🔄 Background location initialization complete: $success");
    }).catchError((e) {
      print("❌ Error in background location initialization: $e");
      _isAsyncInitializing = false;
    });
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

  Future<Map<String, dynamic>> getDeviceContext(
      {bool needLocation = false}) async {
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
        } else if (_currentPosition!.latitude != null &&
            _currentPosition!.longitude != null) {
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

// Also update _getWeatherData to use new function
  Future<String> _getWeatherData() async {
    // If we have cached weather data, use that
    if (_weatherData != null) {
      return "${_weatherData!['main']}, ${_weatherData!['temperature']}°C ${_weatherData!['emoji']}";
    }

    // Otherwise try to fetch fresh data
    final weatherData = await fetchWeatherData();
    if (weatherData != null) {
      return "${weatherData['main']}, ${weatherData['temperature']}°C ${weatherData['emoji']}";
    }

    // Default fallback
    return "Sunny, 28°C ☀️";
  }

  Future<Map<String, dynamic>?> fetchWeatherData() async {
    if (_currentPosition == null) {
      print('Cannot fetch weather: Current position is null');

      // Use a default location for Malaysia (Kuala Lumpur coordinates)
      print('Falling back to default location (Kuala Lumpur)');

      try {
        final defaultLocation = {
          'latitude': 3.1390,
          'longitude': 101.6869,
        };

        final weatherData = await _weatherService.getWeatherByLocation(
            defaultLocation['latitude']!, defaultLocation['longitude']!);

        _weatherData = weatherData;
        _isLoadingWeather = false;

        print(
            'Default weather fetched: ${weatherData['main']} - ${weatherData['emoji']} - ${weatherData['temperature']}°C');

        if (onWeatherUpdated != null) {
          onWeatherUpdated!(weatherData);
        }

        return weatherData;
      } catch (e) {
        _isLoadingWeather = false;
        print('Error fetching default weather: $e');
        return null;
      }
    }

    // Add the missing implementation for when _currentPosition is not null
    print(
        'Fetching weather for location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

    _isLoadingWeather = true;

    try {
      final weatherData = await _weatherService.getWeatherByLocation(
          _currentPosition!.latitude!, _currentPosition!.longitude!);

      _weatherData = weatherData;
      _isLoadingWeather = false;

      print(
          'Weather fetched: ${weatherData['main']} - ${weatherData['emoji']} - ${weatherData['temperature']}°C');

      // Notify listeners if callback is registered
      if (onWeatherUpdated != null) {
        onWeatherUpdated!(weatherData);
      }

      return weatherData;
    } catch (e) {
      _isLoadingWeather = false;
      print('Error fetching weather: $e');
      return null;
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
