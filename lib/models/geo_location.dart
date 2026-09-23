class GeoLocationRecord {
  final int? id;
  final String userId;
  final String syncId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isSynced;

  GeoLocationRecord({
    this.id,
    required this.userId,
    required this.syncId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'sync_id': syncId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory GeoLocationRecord.fromMap(Map<String, dynamic> map) {
    return GeoLocationRecord(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      syncId: (map['sync_id'] as String?) ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int, isUtc: true),
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'local_id': id,
      'sync_id': syncId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  GeoLocationRecord copyWith({
    int? id,
    String? userId,
    String? syncId,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    bool? isSynced,
  }) {
    return GeoLocationRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      syncId: syncId ?? this.syncId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
