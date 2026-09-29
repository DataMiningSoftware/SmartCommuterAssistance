import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/services/auth_service.dart';

void main() {
  test('anonymous profile email derives a stable local key', () {
    expect(
      anonymousProfileEmail('0f3a91c2-8f11-4d5a-9d2b-7c6e5f4a3b2c'),
      'anon_0f3a91c2@local',
    );
  });

  test('anonymous profile email tolerates short and empty ids', () {
    expect(anonymousProfileEmail('abc'), 'anon_abc@local');
    expect(anonymousProfileEmail(''), 'anon_device@local');
  });
}
