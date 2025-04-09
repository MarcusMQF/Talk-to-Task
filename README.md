# Grab Voice Assistant for Drivers

A voice-centric AI assistant for Grab drivers that enables hands-free operation while driving, enhancing safety and convenience.

## Features

- **Voice-First Interface**: Designed primarily for voice interaction to minimize the need for physical interaction with the device while driving
- **Noise-Resistant Voice Recognition**: Optimized for use in noisy environments like a moving vehicle
- **Natural Command Handling**: Processes natural language commands rather than requiring specific phrases
- **Voice Response**: Provides audio feedback to keep drivers' eyes on the road
- **Minimal Visual UI**: Interface designed for glanceability when visual feedback is needed

## Key Use Cases

- Accept/decline ride requests hands-free
- Get navigation instructions by voice
- Call passengers without touching the phone
- Mark arrival, start trip, and end trip using voice commands
- Report issues or problems using voice
- Check earnings and status information

## Technical Stack

- **Flutter**: Cross-platform mobile development framework
- **Speech to Text**: Voice recognition capabilities
- **Flutter TTS**: Text-to-speech for voice responses
- **Provider**: State management
- **RNNoise**: Noise suppression (integration planned)
- **Whisper**: Advanced speech recognition (integration planned)

## Project Structure

The project follows a modular architecture with clear separation of concerns:

- **models/**: Data models for the application
- **providers/**: State management using the Provider pattern
- **screens/**: UI screens for the application
- **services/**: Business logic and services
- **widgets/**: Reusable UI components
- **constants/**: App-wide constants and theme definitions
- **utils/**: Utility functions and helpers

## Getting Started

### Prerequisites

- Flutter SDK (version 3.0+)
- Android Studio / Xcode for device deployment
- A physical device for testing (simulator may not support all voice features)

### Installation

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Connect a physical device
4. Run `flutter run` to start the application

## Voice Commands

The assistant supports the following voice commands:

- "Accept this ride" - Accept the current ride request
- "Decline this ride" - Decline the current ride request
- "Navigate to pickup" - Start navigation to pickup location
- "Call passenger" - Call the current passenger
- "I have arrived" - Mark arrival at pickup location
- "Start trip" - Begin the trip after passenger pickup
- "End trip" - Complete the current trip
- "Report a problem" - Report an issue with the current ride
- "Go offline" - Stop receiving ride requests
- "Go online" - Start receiving ride requests again
- "Check my earnings" - Get current earnings information

## Future Enhancements

- Integration with Grab's API for real ride data
- Improved noise cancellation for better performance in extreme conditions
- Multi-language support for diverse driver regions
- Offline mode for operation in areas with poor connectivity
- Advanced analytics to improve command recognition accuracy over time
