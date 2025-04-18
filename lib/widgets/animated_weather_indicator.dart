import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedWeatherIndicator extends StatefulWidget {
  final String weatherEmoji;
  final String weatherCondition;
  final bool isDarkMode;
  final Color? backgroundColor;
  
  const AnimatedWeatherIndicator({
    Key? key,
    required this.weatherEmoji,
    required this.weatherCondition,
    this.isDarkMode = false,
    this.backgroundColor,
  }) : super(key: key);

  @override
  State<AnimatedWeatherIndicator> createState() => _AnimatedWeatherIndicatorState();
}

class _AnimatedWeatherIndicatorState extends State<AnimatedWeatherIndicator> with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late AnimationController _shakeController;
  late AnimationController _rotateController;
  late Animation<double> _bounceAnimation;
  late Animation<double> _shakeAnimation;
  late Animation<double> _rotateAnimation;
  
  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }
  
  @override
  void didUpdateWidget(AnimatedWeatherIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weatherCondition != widget.weatherCondition) {
      _resetAnimations();
    }
  }
  
  void _setupAnimations() {
    // Bounce animation for sun, clouds
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: 6.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeInOut,
    ));
    
    // Shake animation for rain, snow, thunderstorm
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _shakeAnimation = Tween<double>(
      begin: -3.0,
      end: 3.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
    
    // Rotate animation for tornado, wind
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 2 * pi,
    ).animate(_rotateController);
    
    // Start appropriate animation based on weather
    _updateActiveAnimation();
  }
  
  void _resetAnimations() {
    _bounceController.reset();
    _shakeController.reset();
    _rotateController.reset();
    _updateActiveAnimation();
  }
  
  void _updateActiveAnimation() {
    // Stop all animations first
    _bounceController.stop();
    _shakeController.stop();
    _rotateController.stop();
    
    // Start the appropriate animation based on weather condition
    switch (widget.weatherCondition) {
      case 'Clear':
      case 'Clouds':
        _bounceController.repeat(reverse: true);
        break;
      case 'Rain':
      case 'Drizzle':
      case 'Snow':
      case 'Thunderstorm':
        _shakeController.repeat(reverse: true);
        break;
      case 'Tornado':
      case 'Squall':
        _rotateController.repeat();
        break;
      default:
        _bounceController.repeat(reverse: true);
    }
  }
  
  @override
  void dispose() {
    _bounceController.dispose();
    _shakeController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _bounceController,
        _shakeController,
        _rotateController,
      ]),
      builder: (context, child) {
        Widget emojiWidget = Text(
          widget.weatherEmoji,
          style: const TextStyle(fontSize: 18),
        );
        
        // Apply appropriate animation based on weather condition
        switch (widget.weatherCondition) {
          case 'Clear':
          case 'Clouds':
            emojiWidget = Transform.translate(
              offset: Offset(0, _bounceAnimation.value),
              child: emojiWidget,
            );
            break;
          case 'Rain':
          case 'Drizzle':
          case 'Snow':
          case 'Thunderstorm':
            emojiWidget = Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: emojiWidget,
            );
            break;
          case 'Tornado':
          case 'Squall':
            emojiWidget = Transform.rotate(
              angle: _rotateAnimation.value,
              child: emojiWidget,
            );
            break;
          default:
            emojiWidget = Transform.translate(
              offset: Offset(0, _bounceAnimation.value),
              child: emojiWidget,
            );
        }
        
        // Use the parent container styling instead of adding our own
        return Center(child: emojiWidget);
      },
    );
  }
} 