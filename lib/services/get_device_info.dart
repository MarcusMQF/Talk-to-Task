import 'package:location/location.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart' as geo;

class DeviceInfoService {
  // Services
  final Location _location = Location();
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Cached location data
  LocationData? _currentPosition;
  String _country = "Unknown";
  bool _locationServiceEnabled = false;

  // Initialize location services and get permissions
  Future<bool> initializeLocation() async {
    try {
      // Check if location service is enabled
      _locationServiceEnabled = await _location.serviceEnabled();
      if (!_locationServiceEnabled) {
        _locationServiceEnabled = await _location.requestService();
        if (!_locationServiceEnabled) {
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
      _country = await _getCountryFromCoordinates(
          _currentPosition?.latitude ?? 0.0,
          _currentPosition?.longitude ?? 0.0);

      print("Location initialized: $_country");
      return true;
    } catch (e) {
      print("Error initializing location: $e");
      return false;
    }
  }

  // Get the current location
  Future<LocationData?> getCurrentLocation() async {
    try {
      _currentPosition = await _location.getLocation();
      return _currentPosition;
    } catch (e) {
      print("Error getting current location: $e");
      return null;
    }
  }

  Future<String> _getCountryFromCoordinates(
      double latitude, double longitude) async {
    try {
      if (latitude == 0.0 && longitude == 0.0) {
        return "Malaysia"; // Default for your app's context
      }

      print('Getting country from coordinates: $latitude, $longitude');

      try {
        // Use geo. prefix for placemarkFromCoordinates
        List<geo.Placemark> placemarks =
            await geo.placemarkFromCoordinates(latitude, longitude);

        if (placemarks.isNotEmpty &&
            placemarks.first.country != null &&
            placemarks.first.country!.isNotEmpty) {
          print('Found country: ${placemarks.first.country}');
          return placemarks.first.country!;
        }

        // Fallback if geocoding gives empty result
        return "Malaysia"; // Default for your app's context
      } catch (e) {
        print('Error in geocoding: $e');
        return "Malaysia"; // Default fallback
      }
    } catch (e) {
      print('Error getting country from coordinates: $e');
      return "Malaysia"; // Default fallback
    }
  }

  // Setup location change listener
  void setupLocationListener(Function(LocationData) onLocationChanged) {
    _location.onLocationChanged.listen((LocationData currentLocation) {
      _currentPosition = currentLocation;
      onLocationChanged(currentLocation);
    });
  }

  // Get device context (all device info in one call)
  Future<Map<String, dynamic>> getDeviceContext() async {
    Map<String, dynamic> context = {};

    try {
      if (_country == "Unknown") {
        print('Country is unknown, attempting to initialize location...');
        await initializeLocation();
      }

      // Get battery level
      final batteryLevel = await _battery.batteryLevel;
      context['battery'] = "$batteryLevel%";

      // Get connectivity status
      final connectivityResult = await _connectivity.checkConnectivity();
      context['network'] = _getNetworkType(connectivityResult);

      // Get current time
      final now = DateTime.now();
      context['time'] = DateFormat('h:mm a').format(now);

      // Get weather (mock for now)
      context['weather'] = "Clear";

      // Get location from cached values
      if (_country != "Unknown") {
        context['location'] = _country;
        print('Using cached country: $_country');
      } else {
        // Try to get location one more time
        try {
          final position = await _location.getLocation();
          if (position.latitude != null && position.longitude != null) {
            _country = await _getCountryFromCoordinates(
                position.latitude ?? 0.0, position.longitude ?? 0.0);
            context['location'] = _country;
            print('Got country from fresh coordinates: $_country');
          } else {
            // Last resort: use a hardcoded value based on device locale
            context['location'] = "Malaysia"; // Default for your app's context
            print('Using hardcoded country as last resort');
          }
        } catch (e) {
          print('Error getting fresh location: $e');
          context['location'] = "Malaysia"; // Default fallback
        }
      }

      // Get device info
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        context['device'] = "${androidInfo.model}";
      }

      return context;
    } catch (e) {
      print("Error gathering device context: $e");
      return {
        'battery': "75%",
        'network': "Cellular",
        'time': DateFormat('h:mm a').format(DateTime.now()),
        'weather': "Clear",
        'location': _country,
        'device': "Android"
      };
    }
  }

  // Helper method to convert connectivity result to readable string
  String _getNetworkType(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.mobile:
        return "Cellular";
      case ConnectivityResult.wifi:
        return "WiFi";
      case ConnectivityResult.ethernet:
        return "Ethernet";
      case ConnectivityResult.bluetooth:
        return "Bluetooth";
      case ConnectivityResult.none:
        return "Offline";
      default:
        return "Unknown";
    }
  }
}
