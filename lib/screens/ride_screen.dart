import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'package:flutter/physics.dart';
import '../constants/app_theme.dart';
import '../providers/voice_assistant_provider.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Alignment> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _widthAnimation;
  
  // Request card animation
  late AnimationController _requestCardController;
  late Animation<Offset> _requestCardAnimation;
  
  // Voice button position
  late AnimationController _voiceButtonAnimController;
  Offset _voiceButtonPosition = const Offset(20, 200);
  
  bool _isOnline = false;
  bool _hasActiveRequest = false;
  int _remainingSeconds = 15;
  Timer? _requestTimer;
  
  // Google Maps controller
  GoogleMapController? _mapController;
  
  // Initial camera position (example coordinates - should be replaced with actual pickup location)
  static const LatLng _initialPosition = LatLng(3.1390, 101.6869); // KL coordinates
  
  // Markers for pickup and dropoff locations
  final Set<Marker> _markers = {};
  
  // Timer animations
  late AnimationController _timerShakeController;
  late AnimationController _timerGlowController;
  late Animation<double> _timerShakeAnimation;
  late Animation<double> _timerGlowAnimation;
  
  @override
  void initState() {
    super.initState();
    _setupMarkers();
    _setupAnimations();
    _setupRequestCardAnimations();
    _setupVoiceButtonAnimation();
    _setupTimerAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupVoiceCommandHandler();
    });
  }
  
  @override
  void dispose() {
    _slideController.dispose();
    _requestCardController.dispose();
    _voiceButtonAnimController.dispose();
    _timerShakeController.dispose();
    _timerGlowController.dispose();
    _requestTimer?.cancel();
    _mapController?.dispose();
    final voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
    voiceProvider.removeCommandCallback();
    super.dispose();
  }
  
  void _setupMarkers() {
    _markers.add(
      const Marker(
        markerId: MarkerId('pickup'),
        position: _initialPosition,
        infoWindow: InfoWindow(title: 'Pickup Location'),
      ),
    );
  }

  void _setupRequestCardAnimations() {
    _requestCardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    _requestCardAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Start from below the screen
      end: const Offset(0, 0),   // End at normal position
    ).animate(CurvedAnimation(
      parent: _requestCardController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  void _setupVoiceButtonAnimation() {
    _voiceButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _setupTimerAnimation() {
    // Shake animation
    _timerShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _timerShakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -3).chain(CurveTween(curve: Curves.elasticIn)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -3, end: 3).chain(CurveTween(curve: Curves.elasticIn)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 3, end: 0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 25,
      ),
    ]).animate(_timerShakeController);
    
    // Glow animation
    _timerGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _timerGlowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _timerGlowController,
      curve: Curves.easeInOut,
    ));
    
    // Loop the glow effect
    _timerGlowController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _timerGlowController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _timerGlowController.forward();
      }
    });
  }

  void _snapVoiceButtonToEdge() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Constrain Y position to be within safe bounds
    double safeY = _voiceButtonPosition.dy.clamp(
      120.0, // Stay below top toggle
      screenHeight - 100.0, // Stay above bottom edge
    );
    
    // Determine which side to snap to
    final isLeftHalf = _voiceButtonPosition.dx < (screenWidth / 2);
    final targetX = isLeftHalf ? 20.0 : screenWidth - 84.0; // 84 = button width + margin
    
    setState(() {
      _voiceButtonPosition = Offset(targetX, safeY);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (details.primaryVelocity == null) return;

    final bool isDraggingRight = details.primaryVelocity! > 0;
    final bool shouldToggle = (isDraggingRight && !_isOnline) || (!isDraggingRight && _isOnline);

    if (shouldToggle) {
      _toggleOnlineStatus();
    }

    // Create identical spring simulation for both directions
    const spring = SpringDescription(
      mass: 1,
      stiffness: 500,
      damping: 20,
    );

    final double velocity = details.primaryVelocity! / 1000;
    final double currentValue = _slideController.value;
    final double targetValue = shouldToggle 
        ? (isDraggingRight ? 1.0 : 0.0)
        : (_isOnline ? 1.0 : 0.0);

    final simulation = SpringSimulation(
      spring,
      currentValue,
      targetValue,
      velocity,
    );

    _slideController.animateWith(simulation);
  }

  void _setupAnimations() {
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Create a custom curve that emphasizes the bounce
    final customCurve = CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeInOutCubic),
    );

    _slideAnimation = AlignmentTween(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).animate(customCurve);

    // Create a custom curved animation for consistent behavior
    final curvedAnimation = CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
    );

    // Scale animation for the water droplet effect
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.85)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 1.1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(curvedAnimation);

    // Width animation for the stretching effect
    _widthAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 96, end: 110)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 110, end: 96)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(curvedAnimation);
  }

  void _startRequestTimer() {
    _remainingSeconds = 15;
    _requestTimer?.cancel();
    _requestTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          
          // Start urgent animations when less than or equal to 5 seconds remaining
          if (_remainingSeconds <= 5) {
            if (!_timerGlowController.isAnimating) {
              _timerGlowController.forward();
            }
            _timerShakeController.forward(from: 0.0);
          }
        } else {
          // Time's up - animate the request card sliding out
          _dismissRequest();
          timer.cancel();
          
          // Simulate new request after timeout
          Future.delayed(const Duration(seconds: 2), () {
            if (_isOnline) {
              _showNewRequest();
            }
          });
        }
      });
    });
  }

  void _showNewRequest() {
    setState(() {
      _hasActiveRequest = true;
      _requestCardController.forward(from: 0.0);
      _startRequestTimer();
    });
  }

  void _dismissRequest() {
    // Make sure controller is initialized before animating
    if (!_requestCardController.isAnimating) {
      _requestCardController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _hasActiveRequest = false;
          });
        }
      });
    }
  }

  void _toggleOnlineStatus() {
    // Always update the online state immediately for smooth toggle animation
    setState(() {
      _isOnline = !_isOnline;
      
      if (_isOnline) {
        // Going online - show request card with animation
        _showNewRequest();
      } else {
        // Going offline - but keep request card visible for animation
        if (_hasActiveRequest) {
          // Keep _hasActiveRequest true until animation completes
          _dismissRequest();
          _requestTimer?.cancel();
        }
      }
    });
  }

  Widget _buildOnlineToggle() {
    return Positioned(
      top: 48,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 200,
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              // Calculate drag progress and update controller
              final RenderBox box = context.findRenderObject() as RenderBox;
              final double progress = (details.localPosition.dx / box.size.width)
                  .clamp(0.0, 1.0);
              _slideController.value = progress;
            },
            onHorizontalDragEnd: _handleDragEnd,
            child: Stack(
              children: [
                // Background text
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          'OFFLINE',
                          style: TextStyle(
                            color: !_isOnline ? Colors.grey[400] : Colors.grey[300],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'ONLINE',
                          style: TextStyle(
                            color: _isOnline ? Colors.grey[400] : Colors.grey[300],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Animated sliding button with water droplet effect
                AnimatedBuilder(
                  animation: _slideController,
                  builder: (context, child) {
                    return Align(
                      alignment: _slideAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: _widthAnimation.value,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isOnline 
                                ? [AppTheme.grabGreen, AppTheme.grabGreen.withOpacity(0.8)]
                                : [Colors.grey[400]!, Colors.grey[400]!.withOpacity(0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: (_isOnline ? AppTheme.grabGreen : Colors.grey[400]!)
                                    .withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: _isOnline ? Colors.white : const Color.fromARGB(255, 126, 125, 125),
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isOnline ? 'ONLINE' : 'OFFLINE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Touch target
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _toggleOnlineStatus();
                      if (!_isOnline) {
                        _slideController.reverse();
                      } else {
                        _slideController.forward();
                      }
                    },
                    borderRadius: BorderRadius.circular(24),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard() {
    if (!_hasActiveRequest) return const SizedBox.shrink();
    
    // Determine timer color and style based on remaining time
    final bool isUrgent = _remainingSeconds <= 5;
    final Color timerColor = isUrgent ? Colors.red : AppTheme.grabGreen;
    
    return AnimatedBuilder(
      animation: _requestCardAnimation,
      builder: (context, child) {
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SlideTransition(
            position: _requestCardAnimation,
            child: child!,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timer indicator - more prominent with progress bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isUrgent ? 
                  Colors.red.withOpacity(0.1) : 
                  AppTheme.grabGreen.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // Animated timer row
                  AnimatedBuilder(
                    animation: Listenable.merge([_timerShakeAnimation, _timerGlowAnimation]),
                    builder: (context, child) {
                      return Transform.translate(
                        offset: isUrgent ? Offset(_timerShakeAnimation.value, 0) : Offset.zero,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Animated timer icon with glow effect for urgency
                            Container(
                              decoration: isUrgent ? BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3 + (_timerGlowAnimation.value * 0.5)),
                                    blurRadius: 8 + (_timerGlowAnimation.value * 8),
                                    spreadRadius: 1 + (_timerGlowAnimation.value * 2),
                                  ),
                                ],
                              ) : null,
                              child: Icon(
                                Icons.timer, 
                                size: 15, 
                                color: timerColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_remainingSeconds seconds to respond',
                              style: TextStyle(
                                color: timerColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  // Progress bar for timer
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _remainingSeconds / 15, // Assuming 15 seconds total
                        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isUrgent ? Colors.red : AppTheme.grabGreen
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip type and customer info row
                  Row(
                    children: [
                      // Trip type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.grabGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'GrabCar',
                          style: TextStyle(
                            color: AppTheme.grabGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Customer rating
                      const Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 16),
                          SizedBox(width: 2),
                          Text(
                            '4.8',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Payment method
                      Row(
                        children: [
                          Icon(Icons.payment, size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Cash',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Fare and distance/time row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Fare with larger font
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RM 15.00',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.grabGreen,
                            ),
                          ),
                          // Estimated time
                          Text(
                            'Est. 18 min trip',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      // Distance and ETA info
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.near_me, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              const Text(
                                '3.2 km away',
                                style: TextStyle(
                                  color: AppTheme.grabGrayDark,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'ETA: 8 min',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Navigation card with map preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Quick navigation actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNavigationAction(
                              icon: Icons.directions, 
                              label: 'Directions',
                              onTap: () {
                                if (_mapController != null) {
                                  _mapController!.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      const CameraPosition(
                                        target: _initialPosition,
                                        zoom: 16,
                                        tilt: 45,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            _buildNavigationAction(
                              icon: Icons.call, 
                              label: 'Call',
                              onTap: _showCallDialog,
                            ),
                            _buildNavigationAction(
                              icon: Icons.message, 
                              label: 'Message',
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Location details
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left side - Icons and connecting line
                        SizedBox(
                          width: 36,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              SizedBox(height:11),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.grabGreen.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: AppTheme.grabGreen,
                                  size: 20,
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 2,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.grabGreen.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.flag,
                                  color: AppTheme.grabGreen,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        // Right side - Text content
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pickup text
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pickup',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Sunway Pyramid Mall, PJ',
                                    style: TextStyle(
                                      color: AppTheme.grabBlack,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Main entrance, near Starbucks',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
          
                              SizedBox(height:35),
                              
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Destination',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'KL Sentral, Kuala Lumpur',
                                    style: TextStyle(
                                      color: AppTheme.grabBlack,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Accept/Decline buttons
                  Row(
                    children: [
                      // Decline button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _dismissRequest();
                            // Simulate new request after a delay
                            Future.delayed(const Duration(seconds: 3), () {
                              if (_isOnline && mounted) {
                                _showNewRequest();
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.grabGrayDark,
                            elevation: 0,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _dismissRequest();
                            Future.delayed(const Duration(milliseconds: 500), () {
                              setState(() {
                              });
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.grabGreen,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Accept',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNavigationAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: AppTheme.grabGreen, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      right: 16,
      top: 200,
      child: Column(
        children: [
          // Location focus button
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (_mapController != null) {
                    // Different camera behavior based on whether there's an active request
                    if (_hasActiveRequest) {
                      // Focus on upper half of the screen when there's an active request
                      // Use a higher zoom level and slightly higher target position
                      _mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            // Shift the target position slightly north (upward)
                            target: LatLng(
                              _initialPosition.latitude - 0.005, // Shift north
                              _initialPosition.longitude,
                            ),
                            zoom: 16, // Slightly higher zoom
                            tilt: 0, // No tilt for better overview
                          ),
                        ),
                      );
                    } else {
                      // Standard centering behavior when no active request
                      _mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(
                          const CameraPosition(
                            target: _initialPosition,
                            zoom: 15,
                          ),
                        ),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.my_location, color: AppTheme.grabGreen, size: 20),
                ),
              ),
            ),
          ),
          // Zoom controls container
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Zoom in button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_mapController != null) {
                        _mapController!.animateCamera(CameraUpdate.zoomIn());
                      }
                    },
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.add, color: AppTheme.grabGreen, size: 20),
                    ),
                  ),
                ),
                // Divider
                Container(
                  height: 1,
                  color: Colors.grey.withOpacity(0.2),
                ),
                // Zoom out button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_mapController != null) {
                        _mapController!.animateCamera(CameraUpdate.zoomOut());
                      }
                    },
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.remove, color: AppTheme.grabGreen, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _initialPosition,
              zoom: 15,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),
          _buildOnlineToggle(),
          if (_isOnline) _buildRequestCard(),
          _buildMapControls(),
          _buildDraggableVoiceButton(),
        ],
      ),
    );
  }
  
  Widget _buildDraggableVoiceButton() {
    return Positioned(
      left: _voiceButtonPosition.dx,
      top: _voiceButtonPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _voiceButtonPosition = Offset(
              _voiceButtonPosition.dx + details.delta.dx,
              _voiceButtonPosition.dy + details.delta.dy,
            );
          });
        },
        onPanEnd: (details) {
          _snapVoiceButtonToEdge();
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppTheme.grabGreen.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                final voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
                voiceProvider.startListening();
              },
              customBorder: const CircleBorder(),
              child: const Center(
                child: Icon(
                  Icons.mic,
                  color: AppTheme.grabGreen,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Set up voice command handler
  void _setupVoiceCommandHandler() {
    final voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
    
    voiceProvider.setCommandCallback((command) {
      switch (command) {
        case 'navigate':
          setState(() {
          });
          break;
          
        case 'pick_up':
          setState(() {
          });
          // Could show confirmation dialog here
          break;
          
        case 'start_ride':
          setState(() {
          });
          break;
          
        case 'end_ride':
          // Show completed screen or return to home
          break;
          
        case 'call_passenger':
          // Simulate call intent
          _showCallDialog();
          break;
          
        case 'cancel_ride':
          _showCancelConfirmation();
          break;
      }
    });
  }
  
  void _showCallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Call Passenger'),
        content: Text('Calling Ahmad...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL'),
          ),
        ],
      ),
    );
  }
  
  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Ride?'),
        content: Text('Are you sure you want to cancel this ride? This may affect your cancellation rate.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('NO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('YES'),
          ),
        ],
      ),
    );
  }
} 