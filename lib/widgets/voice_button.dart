import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/voice_assistant_provider.dart';
import '../constants/app_theme.dart';

class VoiceButton extends StatelessWidget {
  final double size;
  final VoidCallback? onPressed;
  
  const VoiceButton({
    super.key,
    this.size = 80.0,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceAssistantProvider>(
      builder: (context, voiceProvider, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            borderRadius: BorderRadius.circular(size / 2),
            onTap: () {
              if (voiceProvider.state == VoiceAssistantState.idle) {
                voiceProvider.startListening();
              } else if (voiceProvider.state == VoiceAssistantState.listening) {
                voiceProvider.stopListening();
              }
              if (onPressed != null) onPressed!();
            },
            child: GestureDetector(
              onLongPress: () {
                if (voiceProvider.state == VoiceAssistantState.idle) {
                  voiceProvider.startListening();
                }
              },
              onLongPressUp: () {
                if (voiceProvider.state == VoiceAssistantState.listening) {
                  voiceProvider.stopListening();
                }
              },
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getBackgroundColor(voiceProvider.state),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.grabGreen.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: -2,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: _buildButtonContent(context, voiceProvider),
              ).animate(
                target: voiceProvider.isListening ? 1 : 0,
              ).scale(
                curve: Curves.easeInOut,
                duration: 300.ms,
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.1, 1.1),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildButtonContent(BuildContext context, VoiceAssistantProvider voiceProvider) {
    switch (voiceProvider.state) {
      case VoiceAssistantState.idle:
        return Icon(
          Icons.mic,
          color: Colors.white,
          size: size * 0.5,
        );
      
      case VoiceAssistantState.listening:
        return Stack(
          alignment: Alignment.center,
          children: [
            _buildPulsingCircle(),
            Icon(
              Icons.mic,
              color: Colors.white,
              size: size * 0.5,
            ),
          ],
        );
      
      case VoiceAssistantState.processing:
        return const CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
          strokeCap: StrokeCap.round,
        );
      
      case VoiceAssistantState.speaking:
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.volume_up,
              color: Colors.white,
              size: size * 0.5,
            ).animate(autoPlay: true).fadeIn().then().shimmer(
              duration: 1000.ms,
              delay: 300.ms,
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: size * 0.7,
                  height: size * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                ).animate(
                  onPlay: (controller) => controller.repeat(),
                  autoPlay: true,
                ).custom(
                  duration: 2000.ms,
                  builder: (context, value, child) {
                    final wave = (value * 4 - 1).abs();
                    return Container(
                      width: size * (0.6 + wave * 0.1),
                      height: size * (0.6 + wave * 0.1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3 - wave * 0.25),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      
      case VoiceAssistantState.error:
        return Icon(
          Icons.error_outline,
          color: Colors.white,
          size: size * 0.5,
        );
    }
  }
  
  Widget _buildPulsingCircle() {
    return Animate(
      autoPlay: true,
      onComplete: (controller) => controller.repeat(),
      effects: [
        ScaleEffect(
          begin: const Offset(0.5, 0.5),
          end: const Offset(1.0, 1.0),
          duration: 1000.ms,
          curve: Curves.easeInOut,
        ),
        FadeEffect(
          begin: 0.7,
          end: 0.3,
          duration: 1000.ms,
          curve: Curves.easeInOut,
        ),
      ],
      child: Container(
        width: size * 0.8,
        height: size * 0.8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }
  
  Color _getBackgroundColor(VoiceAssistantState state) {
    switch (state) {
      case VoiceAssistantState.idle:
        return AppTheme.grabGreen;
      case VoiceAssistantState.listening:
        return AppTheme.grabGreenDark;
      case VoiceAssistantState.processing:
        return AppTheme.grabGreen.withOpacity(0.7);
      case VoiceAssistantState.speaking:
        return AppTheme.grabGreenLight;
      case VoiceAssistantState.error:
        return AppTheme.errorRed;
    }
  }
} 