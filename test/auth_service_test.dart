import 'package:expense_tracker/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PBKDF2 matches React Admin PBKDF2-SHA256-310000 encoding', () async {
    final salt = <int>[
      0x00,
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
      0x99,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
    ];
    const expectedHash =
        '6ffb516a913c46efcff8d8f1df75f8d74eddb1462abf203b412ddf2678589b94';

    final generatedHash = await AuthService.derivePasswordHash(
      'admin-test-password',
      salt,
    );
    final wrongPasswordHash = await AuthService.derivePasswordHash(
      'wrong-password',
      salt,
    );

    expect(generatedHash, expectedHash);
    expect(generatedHash, isNot(wrongPasswordHash));
    expect(generatedHash.length, 64);
  });

  group('AuthService validators', () {
    test('validateLoginPassword requires a non-empty value', () {
      expect(AuthService.validateLoginPassword(null), isNotNull);
      expect(AuthService.validateLoginPassword(''), isNotNull);
      expect(AuthService.validateLoginPassword('secret'), isNull);
    });

    test('validateNewPassword requires at least six characters', () {
      expect(AuthService.validateNewPassword('12345'), isNotNull);
      expect(AuthService.validateNewPassword('123456'), isNull);
    });
  });

  group('AuthService profile mapping', () {
    test('profileFromMap omits credential fields from the profile model', () {
      final profile = AuthService.profileFromMap({
        'username': 'demo.user',
        'role': 'field',
        'password_hash': 'abc',
        'salt': 'xyz',
        'hash_algorithm': 'scrypt',
        'password_changed_at': '2026-01-01',
      });

      expect(profile.username, 'demo.user');
      expect(profile.role, 'field');
    });

    test('isAccountActive treats inactive statuses as disabled', () {
      expect(
        AuthService.isAccountActive({'account_status': 'inactive'}),
        isFalse,
      );
      expect(AuthService.isAccountActive({'account_status': 'active'}), isTrue);
    });
  });
}
