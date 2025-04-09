import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/voice_assistant_provider.dart';
import '../constants/app_theme.dart';

class VoiceFeedback extends StatelessWidget {
  final bool showTranscription;
  final bool showResponse;
  
  const VoiceFeedback({
    super.key,
    this.showTranscription = true,
    this.showResponse = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceAssistantProvider>(
      builder: (context, voiceProvider, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTranscription && voiceProvider.lastWords.isNotEmpty)
              _buildTranscriptionText(context, voiceProvider),
            
            if (showResponse && 
                voiceProvider.responseMessage.isNotEmpty && 
                voiceProvider.state != VoiceAssistantState.listening)
              _buildResponseText(context, voiceProvider),
            
            if (voiceProvider.state == VoiceAssistantState.error)
              _buildErrorText(context, voiceProvider),
          ],
        );
      },
    );
  }
  
  Widget _buildTranscriptionText(BuildContext context, VoiceAssistantProvider voiceProvider) {
    final isListening = voiceProvider.state == VoiceAssistantState.listening;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: isListening 
            ? AppTheme.grabGreen.withOpacity(0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isListening 
              ? AppTheme.grabGreen.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isListening)
            Text(
              'Listening...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.grabGreenDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            voiceProvider.lastWords,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppTheme.grabBlack,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate(
      target: isListening ? 1 : 0,
    ).fadeIn(
      duration: 200.ms,
    ).then(delay: 100.ms).slide(
      begin: const Offset(0, 0.1),
      end: const Offset(0, 0),
      duration: 300.ms,
      curve: Curves.easeOutCubic,
    );
  }
  
  Widget _buildResponseText(BuildContext context, VoiceAssistantProvider voiceProvider) {
    final isSpeaking = voiceProvider.state == VoiceAssistantState.speaking;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: isSpeaking
            ? AppTheme.grabGreen.withOpacity(0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isSpeaking 
              ? AppTheme.grabGreen.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
        ),
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: AppTheme.grabGreen.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          if (isSpeaking)
            const Icon(
              Icons.volume_up,
              color: AppTheme.grabGreen,
              size: 24,
            ).animate(autoPlay: true).fadeIn().then().shimmer(
              duration: 1000.ms,
              delay: 300.ms,
            ),
          if (isSpeaking)
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              voiceProvider.responseMessage,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: AppTheme.grabBlack,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
      duration: 300.ms,
    ).then(delay: 100.ms).slide(
      begin: const Offset(0, 0.2),
      end: const Offset(0, 0),
      duration: 300.ms,
      curve: Curves.easeOutCubic,
    );
  }
  
  Widget _buildErrorText(BuildContext context, VoiceAssistantProvider voiceProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: AppTheme.errorRed.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppTheme.errorRed,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              voiceProvider.errorMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.errorRed.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
      duration: 200.ms,
    ).then().shake(
      duration: 300.ms,
      curve: Curves.easeInOut,
    );
  }
} 