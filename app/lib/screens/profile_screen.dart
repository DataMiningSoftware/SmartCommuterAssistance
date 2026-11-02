import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_features.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/accessibility_service.dart';
import '../services/auth_service.dart';
import '../services/offline_mode_service.dart';
import '../services/education_service.dart';
import '../services/locale_controller.dart';
import '../services/location_privacy_service.dart';
import '../services/ml_consent_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/theme_controller.dart';
import '../widgets/app_page_title.dart';
import 'education_screen.dart';
import 'friends_screen.dart';
import 'route_builder_screen.dart';
import 'support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  bool _offlineModeEnabled = false;
  bool _accessibilityEnabled = false;
  bool _locationConsent = false;
  bool _mlConsent = false;
  final AuthService _authService = AuthService();
  MasteryStats? _mastery;

  @override
  void initState() {
    super.initState();
    _loadPrivacyConsent();
    if (AppFeatures.educationEnabled) {
      _loadMastery();
    }
    _offlineModeEnabled = OfflineModeService.instance.enabled.value;
    _accessibilityEnabled = AccessibilityService.instance.enabled.value;
  }

  Future<void> _loadPrivacyConsent() async {
    final consented = await LocationPrivacyService.hasConsent();
    await MlConsentService.instance.load();
    if (mounted) {
      setState(() {
        _locationConsent = consented;
        _mlConsent = MlConsentService.instance.granted;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    final l10n = AppLocalizations.of(context);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showProfileMessage(l10n.locationServicesOff);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showProfileMessage(l10n.locationPermissionDenied);
      }
    } catch (_) {}
  }

  void _showProfileMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadMastery() async {
    final stats = await EducationService.instance.getMasteryStats();
    if (mounted) setState(() => _mastery = stats);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final user = _authService.currentUser.value;
    final anonymous = _authService.isAnonymous;
    final userName =
        anonymous ? l10n.profileCommuter : (user?.name ?? l10n.profileUserFallback);
    final userEmail = anonymous
        ? l10n.profileNoAccount
        : (user?.email ?? 'no-email@example.com');
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: AppPageTitle(
          icon: Icons.person_rounded,
          leadingText: 'Commute',
          accentText: 'Hub',
          badgeText: l10n.navProfile.toUpperCase(),
          subtitle: l10n.preferencesTitle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color:
                      Theme.of(context).dividerColor.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userEmail,
                        style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                if (!anonymous)
                  IconButton(
                    onPressed: () => _showEditProfile(context),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.profileEditTooltip,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_mastery != null) ...[
            _MasteryPanel(stats: _mastery!),
            const SizedBox(height: 20),
          ],
          Text(l10n.preferencesTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              SwitchListTile(
                value: _notificationsEnabled,
                onChanged: (v) => setState(() => _notificationsEnabled = v),
                title: Text(l10n.pushNotificationsTitle),
                subtitle: Text(l10n.pushNotificationsSubtitle),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _offlineModeEnabled,
                onChanged: (v) async {
                  await OfflineModeService.instance.setEnabled(v);
                  if (!mounted) return;
                  setState(() => _offlineModeEnabled = v);
                },
                title: Text(l10n.offlineModeTitle),
                subtitle: Text(l10n.offlineModeSubtitle),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _locationConsent,
                onChanged: (v) async {
                  await LocationPrivacyService.setConsent(v);
                  if (v) {
                    await _requestLocationPermission();
                  }
                  if (!mounted) return;
                  setState(() => _locationConsent = v);
                },
                title: Text(l10n.locationSharingTitle),
                subtitle: Text(l10n.locationSharingSubtitle),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _mlConsent,
                onChanged: (v) async {
                  await MlConsentService.instance.setConsent(v);
                  setState(() => _mlConsent = v);
                },
                title: Text(l10n.mlConsentTitle),
                subtitle: Text(l10n.mlConsentSubtitle),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _accessibilityEnabled,
                onChanged: (v) async {
                  await AccessibilityService.instance.setEnabled(v);
                  if (!mounted) return;
                  setState(() => _accessibilityEnabled = v);
                },
                title: Text(l10n.accessibilityTitle),
                subtitle: Text(l10n.accessibilitySubtitle),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: ThemeController.instance.mode.value == ThemeMode.dark,
                onChanged: (v) async {
                  await ThemeController.instance.toggle();
                  setState(() {});
                },
                title: Text(l10n.darkModeTitle),
                subtitle: Text(l10n.darkModeSubtitle),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.translate_rounded,
                    color: theme.colorScheme.primary),
                title: Text(l10n.languageTitle),
                subtitle: Text(_currentLanguageLabel(l10n)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showLanguageDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(l10n.dataAttributionsTitle,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              ListTile(
                leading: Icon(Icons.map_outlined,
                    color: theme.colorScheme.primary),
                title: Text(l10n.mapTilesTitle),
                subtitle: Text(l10n.mapTilesSource),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cloud_outlined,
                    color: theme.colorScheme.primary),
                title: Text(l10n.weatherTitle),
                subtitle: Text(l10n.weatherSource),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.train_outlined,
                    color: theme.colorScheme.primary),
                title: Text(l10n.transitScheduleTitle),
                subtitle: Text(l10n.transitScheduleSource),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l10n.quickActionsTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              _ActionRow(
                  icon: Icons.alt_route_rounded,
                  title: l10n.routeBuilderTitle,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RouteBuilderScreen()))),
              const Divider(height: 1),
              if (AppFeatures.socialEnabled) ...[
                _ActionRow(
                    icon: Icons.people_outline,
                    title: l10n.friendsTitle,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FriendsScreen()))),
                const Divider(height: 1),
              ],
              if (AppFeatures.educationEnabled) ...[
                _ActionRow(
                    icon: Icons.school_outlined,
                    title: l10n.learnTheRailsTitle,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EducationScreen()))),
                const Divider(height: 1),
              ],
              _ActionRow(
                  icon: Icons.favorite_outline,
                  title: l10n.favoriteRoutesTitle,
                  onTap: () {}),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.history,
                  title: l10n.travelHistoryTitle,
                  onTap: () {}),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.notifications_active_outlined,
                  title: l10n.testNotificationTitle,
                  onTap: () async {
                    final service = NotificationService();
                    await service.requestPermissions();
                    await service.showNotification(
                      title: 'Smart Commuter Assistant+',
                      body: l10n.testNotificationBody,
                      type: NotificationType.info,
                    );
                  }),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.help_outline,
                  title: l10n.helpSupportTitle,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SupportScreen()))),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.info_outline,
                title: l10n.aboutTitle,
                onTap: () => _showAboutDialog(context),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.privacy_tip_outlined,
                title: l10n.privacyPolicyTitle,
                onTap: () => launchUrl(
                  Uri.parse(
                    'https://dataminingsoftware.github.io/SmartCommuterAssistance/privacy.html',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!anonymous) ...[
            OutlinedButton.icon(
              onPressed: () async {
                await _authService.logout();
              },
              icon: const Icon(Icons.logout),
              label: Text(l10n.logoutButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: () => _confirmDeleteAccount(context),
            child: Text(
              anonymous ? l10n.deleteMyDataButton : l10n.deleteAccountButton,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = LocaleController.instance.locale.value?.languageCode;
    showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.languageTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'system'),
            child: Row(
              children: [
                Icon(current == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.languageSystemOption)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'en'),
            child: Row(
              children: [
                Icon(current == 'en'
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.languageEnglishOption)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'ms'),
            child: Row(
              children: [
                Icon(current == 'ms'
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.languageMalayOption)),
              ],
            ),
          ),
        ],
      ),
    ).then((selected) async {
      if (selected == null) return;
      if (selected == 'system') {
        await LocaleController.instance.setLocale(null);
      } else {
        await LocaleController.instance.setLocale(Locale(selected));
      }
    });
  }

  String _currentLanguageLabel(AppLocalizations l10n) {
    final locale = LocaleController.instance.locale.value;
    switch (locale?.languageCode) {
      case 'en':
        return l10n.languageEnglishOption;
      case 'ms':
        return l10n.languageMalayOption;
      default:
        return l10n.languageSystemOption;
    }
  }

  void _showEditProfile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileService = ProfileService.instance;
    final profile = profileService.currentProfile.value;
    final handleController = TextEditingController(text: profile?.handle ?? '');
    final nameController =
        TextEditingController(text: profile?.displayName ?? '');
    final bioController = TextEditingController(text: profile?.bio ?? '');
    final colorController =
        TextEditingController(text: profile?.avatarColor ?? '');
    final homeController =
        TextEditingController(text: profile?.homeStationId ?? '');
    final lineController =
        TextEditingController(text: profile?.favoriteLine ?? '');
    bool allowSearch = profile?.allowHandleSearch ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.editProfileTitle,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: handleController,
                  decoration:
                      InputDecoration(labelText: l10n.handleLabel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration:
                      InputDecoration(labelText: l10n.displayNameLabel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bioController,
                  decoration: InputDecoration(labelText: l10n.bioLabel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: colorController,
                  decoration: InputDecoration(
                      labelText: l10n.avatarColorLabel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: homeController,
                  decoration:
                      InputDecoration(labelText: l10n.homeStationLabel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lineController,
                  decoration:
                      InputDecoration(labelText: l10n.favoriteLineLabel),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allowSearch,
                  onChanged: (v) => setModalState(() => allowSearch = v),
                  title: Text(l10n.allowFindByHandle),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    await profileService.updateProfile({
                      'handle': handleController.text.trim(),
                      'display_name': nameController.text.trim(),
                      'bio': bioController.text.trim(),
                      'avatar_color': colorController.text.trim(),
                      'home_station_id': homeController.text.trim(),
                      'favorite_line': lineController.text.trim(),
                      'allow_handle_search': allowSearch,
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(l10n.saveButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final anonymousUser = _authService.isAnonymous;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(anonymousUser
            ? l10n.profileDeleteDataDialogTitle
            : l10n.profileDeleteAccountDialogTitle),
        content: Text(anonymousUser
            ? l10n.profileDeleteDataDialogBody
            : l10n.profileDeleteAccountDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteButton,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final deleted = await _authService.deleteAccount();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? l10n.accountDeleted : l10n.deleteAccountFailed,
        ),
      ),
    );
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    var version = '1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aboutDialogTitle),
        content: Text(l10n.aboutDialogBody(version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.okButton),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;

  const _Panel({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.12)),
      ),
      child: Column(children: children),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _MasteryPanel extends StatelessWidget {
  final MasteryStats stats;

  const _MasteryPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final total = stats.totalAttempts;
    final independence = total == 0
        ? 0
        : (stats.correctAttempts / total * 100).round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(l10n.railIndependenceTitle,
                  style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.railIndependenceBody(
                stats.stationsLearned, stats.accuracyPct.round()),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: independence / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}
