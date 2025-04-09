class Location {
  final String address;
  final double latitude;
  final double longitude;
  
  const Location({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

class Passenger {
  final String name;
  final String phoneNumber;
  final double rating;
  final int totalRides;
  final String? photoUrl;
  
  const Passenger({
    required this.name,
    required this.phoneNumber,
    required this.rating,
    required this.totalRides,
    this.photoUrl,
  });
}

enum RideStatus {
  pending,
  accepted,
  arrived,
  started,
  completed,
  cancelled
}

class Ride {
  final String id;
  final RideStatus status;
  final Location pickup;
  final Location dropoff;
  final Passenger passenger;
  final double fare;
  final double distance;
  final int estimatedTimeInMinutes;
  final DateTime createdAt;
  
  const Ride({
    required this.id,
    required this.status,
    required this.pickup,
    required this.dropoff,
    required this.passenger,
    required this.fare,
    required this.distance,
    required this.estimatedTimeInMinutes,
    required this.createdAt,
  });
  
  // Sample ride for demo purposes
  static Ride get sampleRide => Ride(
    id: 'RIDE-123456',
    status: RideStatus.started,
    pickup: const Location(
      address: '28, Jalan Universiti, 46200 Petaling Jaya',
      latitude: 3.1190,
      longitude: 101.6389,
    ),
    dropoff: const Location(
      address: 'Pavilion, Bukit Bintang, 55100 Kuala Lumpur',
      latitude: 3.1488,
      longitude: 101.7133,
    ),
    passenger: const Passenger(
      name: 'Sarah Lim',
      phoneNumber: '+60123456789',
      rating: 4.8,
      totalRides: 125,
    ),
    fare: 23.50,
    distance: 8.7,
    estimatedTimeInMinutes: 25,
    createdAt: DateTime.now(),
  );
} 