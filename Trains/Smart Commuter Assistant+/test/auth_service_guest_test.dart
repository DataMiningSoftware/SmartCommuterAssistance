import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter_assistant/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initialize falls back to guest mode when Supabase is unavailable',
      () async {
    final auth = AuthService();
    await auth.initialize();

    expect(auth.currentUser.value, isNotNull);
    expect(auth.currentUser.value!.email, 'guest@local');
    expect(auth.isGuestMode, isTrue);
  });
}
