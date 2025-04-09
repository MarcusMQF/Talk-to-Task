class VoiceCommand {
  final String command;
  final String description;
  final List<String> examples;
  final List<String> triggers;
  
  const VoiceCommand({
    required this.command,
    required this.description,
    required this.examples,
    required this.triggers,
  });
}

// Define common voice commands for Grab drivers
class VoiceCommands {
  static const List<VoiceCommand> commands = [
    VoiceCommand(
      command: 'accept_ride',
      description: 'Accept the current ride request',
      examples: ['Accept this ride', 'Take this passenger'],
      triggers: ['accept', 'take', 'confirm', 'yes'],
    ),
    VoiceCommand(
      command: 'decline_ride',
      description: 'Decline the current ride request',
      examples: ['Decline this ride', 'Skip this passenger'],
      triggers: ['decline', 'skip', 'reject', 'no'],
    ),
    VoiceCommand(
      command: 'navigate',
      description: 'Start navigation to pickup or destination',
      examples: ['Navigate to pickup', 'Start directions', 'Go to destination'],
      triggers: ['navigate', 'directions', 'go to', 'take me to'],
    ),
    VoiceCommand(
      command: 'call_passenger',
      description: 'Call the passenger',
      examples: ['Call passenger', 'Contact rider'],
      triggers: ['call', 'contact', 'phone', 'dial'],
    ),
    VoiceCommand(
      command: 'check_earnings',
      description: 'Check your current earnings',
      examples: ['How much have I earned today?', 'Check my earnings'],
      triggers: ['earnings', 'earned', 'income', 'money'],
    ),
    VoiceCommand(
      command: 'mark_arrived',
      description: 'Mark that you have arrived at pickup location',
      examples: ['I have arrived', 'Mark as arrived'],
      triggers: ['arrived', 'here', 'reached', 'at location'],
    ),
    VoiceCommand(
      command: 'start_trip',
      description: 'Start the trip after picking up passenger',
      examples: ['Start trip', 'Begin journey'],
      triggers: ['start trip', 'begin', 'start journey', 'picked up'],
    ),
    VoiceCommand(
      command: 'end_trip',
      description: 'End the current trip',
      examples: ['End trip', 'Complete ride', 'Finish journey'],
      triggers: ['end', 'complete', 'finish', 'drop off'],
    ),
    VoiceCommand(
      command: 'report_issue',
      description: 'Report an issue with the current ride',
      examples: ['Report a problem', 'Something is wrong'],
      triggers: ['problem', 'issue', 'wrong', 'report', 'help'],
    ),
    VoiceCommand(
      command: 'go_offline',
      description: 'Go offline and stop receiving ride requests',
      examples: ['Go offline', 'Stop receiving rides'],
      triggers: ['offline', 'stop', 'break', 'pause'],
    ),
    VoiceCommand(
      command: 'go_online',
      description: 'Go online and start receiving ride requests',
      examples: ['Go online', 'Start receiving rides'],
      triggers: ['online', 'start', 'active', 'available'],
    ),
    VoiceCommand(
      command: 'open_ai',
      description: 'Open the AI Chat screen',
      examples: ['Open AI chat', 'Start AI chat', 'Chat with AI'],
      triggers: ['open ai', 'ai chat', 'chat with ai'],
    ),
  ];
}