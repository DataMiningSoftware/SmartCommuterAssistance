import 'package:flutter_test/flutter_test.dart';
import 'package:dynoc/services/auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('initialize falls back to guest mode when Supabase is unavailable',
      () async {
    final auth = AuthService();
    await auth.initialize();

    expect(auth.currentUser.value, isNotNull);
    expect(auth.currentUser.value!.email, 'guest@local');
    expect(auth.isGuestMode, isTrue);
  });
}
