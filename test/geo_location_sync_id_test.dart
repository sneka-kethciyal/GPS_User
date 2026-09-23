import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/geo_location.dart';

void main() {
  test('GPS records keep a stable sync id across retries', () {
    final timestamp = DateTime.utc(2026, 9, 21, 9, 0);
    final record = GeoLocationRecord(
      id: 42,
      userId: 'user-1',
      syncId: 'gps-stable-id-123',
      latitude: 12.9716,
      longitude: 77.5946,
      timestamp: timestamp,
    );

    final encoded = record.toMap();
    final decoded = GeoLocationRecord.fromMap(encoded);

    expect(decoded.syncId, 'gps-stable-id-123');
    expect(decoded.id, 42);
    expect(decoded.latitude, 12.9716);
    expect(decoded.longitude, 77.5946);
    expect(decoded.timestamp, timestamp);
    expect(decoded.isSynced, isFalse);

    final retryPayload = decoded.toFirestore();
    expect(retryPayload['sync_id'], decoded.syncId);
    expect(retryPayload['local_id'], 42);
    expect(retryPayload['latitude'], 12.9716);
    expect(retryPayload['longitude'], 77.5946);
    expect(retryPayload['timestamp'], timestamp.toIso8601String());

    final retriedAgain = GeoLocationRecord.fromMap(decoded.toMap());
    expect(retriedAgain.syncId, record.syncId);
  });
}
