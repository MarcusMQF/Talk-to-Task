import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_assistant_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/voice_button.dart';
import '../widgets/voice_feedback.dart';
import '../constants/app_theme.dart';
import 'ride_screen.dart';
import '../services/audio_processing_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isOnline = true;
  late VoiceAssistantProvider _voiceProvider; // Store a reference to the provider
  final AudioProcessingService _audioProcessingService = AudioProcessingService();
  
  @override
  void initState() {
    super.initState();
    
    // Store reference to provider
    _voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
    
    // Initialize AudioProcessingService with the current online status
    _audioProcessingService.updateGeminiPromptContext(
      isOnline: _isOnline,
      hasActiveRequest: false,
    );
    
    // Set up command handler after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupVoiceCommandHandler();
    });
  }
  
  @override
  void dispose() {
    // Remove command handler using stored reference
    _voiceProvider.removeCommandCallback();
    super.dispose();
  }
  
  // Helper method to update online status and Gemini context
  void _updateOnlineStatus(bool isOnline) {
    setState(() {
      _isOnline = isOnline;
      
      // Update AudioProcessingService's Gemini instance
      _audioProcessingService.updateGeminiPromptContext(
        isOnline: _isOnline,
        hasActiveRequest: false,
      );
    });
  }
  
  void _setupVoiceCommandHandler() {
    _voiceProvider.setCommandCallback((command) {
      switch (command) {
        case 'accept_ride':
          // Navigate to ride screen after a short delay
          Future.delayed(const Duration(milliseconds: 1500), () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RideScreen()),
            );
          });
          break;
        case 'go_offline':
          _updateOnlineStatus(false);
          // Show a snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are now offline'),
              backgroundColor: Colors.blueGrey,
            ),
          );
          break;
        case 'go_online':
          _updateOnlineStatus(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are now online'),
              backgroundColor: AppTheme.grabGreen,
            ),
          );
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grab Driver', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.grabGreen,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
          splashRadius: 0.1,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
            splashRadius: 0.1,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton(
              onPressed: () {
                _updateOnlineStatus(!_isOnline);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _isOnline ? Colors.red : Colors.white,
                foregroundColor: _isOnline ? Colors.white : AppTheme.grabGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
              child: Text(_isOnline ? 'Go Offline' : 'Go Online'),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              color: AppTheme.grabGreen,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ahmad Rizal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Driver ID: 12345678',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car, color: AppTheme.grabGreen),
              title: const Text('My Vehicles'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.history, color: AppTheme.grabGreen),
              title: const Text('Trip History'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.attach_money, color: AppTheme.grabGreen),
              title: const Text('Earnings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.message, color: AppTheme.grabGreen),
              title: const Text('Messages'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: AppTheme.grabGreen),
              title: const Text('Saved Places'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Theme.of(context).brightness == Brightness.dark 
                  ? Icons.light_mode 
                  : Icons.dark_mode,
                color: AppTheme.grabGreen,
              ),
              title: const Text('Toggle Theme'),
              onTap: () {
                Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                children: [
                  // Status Card
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Status',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _isOnline 
                                    ? 'You are online and ready for trips' 
                                    : 'You are offline',
                                  style: TextStyle(
                                    color: _isOnline ? AppTheme.grabGreen : Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isOnline ? AppTheme.grabGreen : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: _isOnline 
                                  ? null 
                                  : Border.all(color: Colors.grey),
                              ),
                              child: Text(
                                _isOnline ? 'ACTIVE' : 'INACTIVE',
                                style: TextStyle(
                                  color: _isOnline ? Colors.white : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Today's Summary
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Today\'s Summary',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  icon: Icons.navigation,
                                  label: 'Trips',
                                  value: '8',
                                ),
                                _buildSummaryItem(
                                  icon: Icons.access_time,
                                  label: 'Hours',
                                  value: '6h 30m',
                                ),
                                _buildSummaryItem(
                                  icon: Icons.attach_money,
                                  label: 'Earnings',
                                  value: 'RM 150.75',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Recent Trips
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Recent Trips',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {},
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.grabGreen,
                                  ),
                                  child: const Text('View All'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildTripItem(
                              time: '10:30 AM',
                              pickup: '123 Main St',
                              dropoff: '456 Market St',
                              amount: 'RM 24.50',
                            ),
                            const Divider(),
                            _buildTripItem(
                              time: '12:15 PM',
                              pickup: '789 Park Ave',
                              dropoff: '321 Lake Blvd',
                              amount: 'RM 18.75',
                            ),
                            const Divider(),
                            _buildTripItem(
                              time: '2:45 PM',
                              pickup: '555 Ocean Dr',
                              dropoff: '777 Mountain Rd',
                              amount: 'RM 32.00',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Positioned Voice Feedback
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Consumer<VoiceAssistantProvider>(
                builder: (context, voiceProvider, _) {
                  if (voiceProvider.state == VoiceAssistantState.idle) {
                    return const SizedBox.shrink();
                  }
                  
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: VoiceFeedback(),
                  );
                },
              ),
            ),
            
            // Floating Voice Assistant Button
            const Positioned(
              right: 16,
              bottom: 16,
              child: VoiceButton(
                size: 60,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.grabGreen.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: AppTheme.grabGreen,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTripItem({
    required String time,
    required String pickup,
    required String dropoff,
    required String amount,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.grabGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.access_time,
              color: AppTheme.grabGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$pickup → $dropoff',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: const TextStyle(
              color: AppTheme.grabGreen,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
} 