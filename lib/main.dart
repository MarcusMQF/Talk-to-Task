import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'constants/app_theme.dart';
import 'providers/voice_assistant_provider.dart';
import 'providers/theme_provider.dart';
import 'services/get_device_info.dart';
import 'screens/ride_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request permissions at startup
  await _requestPermissions();
  
  final deviceInfoService = DeviceInfoService();
  await deviceInfoService.initialize();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  // Request location permissions
  await Permission.locationWhenInUse.request();
  
  // Request other permissions your app needs
  await Permission.microphone.request();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VoiceAssistantProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Talk To Task',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            // Use a permission check before showing the main screen
            home: const PermissionGatewayScreen(),
          );
        },
      ),
    );
  }
}

// New screen to handle permissions properly
class PermissionGatewayScreen extends StatefulWidget {
  const PermissionGatewayScreen({super.key});

  @override
  State<PermissionGatewayScreen> createState() => _PermissionGatewayScreenState();
}

class _PermissionGatewayScreenState extends State<PermissionGatewayScreen> {
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Check if permissions are granted
    final locationStatus = await Permission.locationWhenInUse.status;
    final microphoneStatus = await Permission.microphone.status;
    
    if (mounted) {
      setState(() {
        _checkingPermissions = false;
      });
    }
    
    // If both permissions are granted, proceed to main screen
    if (locationStatus.isGranted && microphoneStatus.isGranted) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RideScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermissions) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Location and Microphone Access Required',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This app needs access to your location and microphone to provide navigation and voice assistance features.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                // Request permissions again
                await _requestPermissions();
                await _checkPermissions();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Grant Permissions', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
