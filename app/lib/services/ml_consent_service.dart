import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MlConsentService {
  MlConsentService._();

  static final MlConsentService instance = MlConsentService._();

  static const String policyVersion = '2026-09-29';
  static const String _grantedKey = 'ml_training_consent_granted';
  static const String _askedKey = 'ml_training_consent_asked';

  bool _granted = false;
  bool get granted => _granted;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _granted = prefs.getBool(_grantedKey) ?? false;
  }

  Future<bool> hasBeenAsked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_askedKey) ?? false;
  }

  Future<void> setConsent(bool granted, {String source = 'profile'}) async {
    _granted = granted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_grantedKey, granted);
    await prefs.setBool(_askedKey, true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      await client.from('profiles').upsert({
        'id': userId,
        'ml_training_consent': granted,
        'consent_policy_version': policyVersion,
        'consent_updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await client.from('consent_events').insert({
        'user_id': userId,
        'granted': granted,
        'policy_version': policyVersion,
        'source': source,
      });
    } catch (_) {
      _granted = granted;
    }
  }
}
