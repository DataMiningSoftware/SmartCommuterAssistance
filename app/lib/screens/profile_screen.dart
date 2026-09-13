import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/location_privacy_service.dart';
import '../services/profile_service.dart';
import '../services/theme_controller.dart';
import '../widgets/app_page_title.dart';
import 'education_screen.dart';
import 'friends_screen.dart';

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
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadPrivacyConsent();
  }

  Future<void> _loadPrivacyConsent() async {
    final consented = await LocationPrivacyService.hasConsent();
    if (mounted) setState(() => _locationConsent = consented);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _authService.currentUser.value;
    final userName = user?.name ?? 'User';
    final userEmail = user?.email ?? 'no-email@example.com';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.person_rounded,
          leadingText: 'Commute',
          accentText: 'Hub',
          badgeText: 'PROFILE',
          subtitle: 'Preferences',
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
                IconButton(
                  onPressed: () => _showEditProfile(context),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit profile',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 20),
          Text('Preferences', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              SwitchListTile(
                value: _notificationsEnabled,
                onChanged: (v) => setState(() => _notificationsEnabled = v),
                title: const Text('Push Notifications'),
                subtitle: const Text('Delay and route alerts'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _offlineModeEnabled,
                onChanged: (v) => setState(() => _offlineModeEnabled = v),
                title: const Text('Offline Mode'),
                subtitle: const Text('Cache schedules for weak coverage'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _locationConsent,
                onChanged: (v) async {
                  await LocationPrivacyService.setConsent(v);
                  setState(() => _locationConsent = v);
                },
                title: const Text('Location Sharing'),
                subtitle: const Text(
                  'Coordinates rounded to ~1 km before sending',
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _accessibilityEnabled,
                onChanged: (v) => setState(() => _accessibilityEnabled = v),
                title: const Text('Accessibility'),
                subtitle: const Text('Larger labels and stronger contrast'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: ThemeController.instance.mode.value == ThemeMode.dark,
                onChanged: (v) async {
                  await ThemeController.instance.toggle();
                  setState(() {});
                },
                title: const Text('Dark Mode'),
                subtitle: const Text('Enable dark theme for the app'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Data Attributions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              ListTile(
                leading: Icon(Icons.map_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Map tiles'),
                subtitle: const Text('© CartoDB'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cloud_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Weather'),
                subtitle: const Text('Weather data by Open-Meteo.com'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.train_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Transit schedule'),
                subtitle: const Text(
                    '© Prasarana Malaysia via data.gov.my'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Quick Actions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              _ActionRow(
                  icon: Icons.people_outline,
                  title: 'Friends',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FriendsScreen()))),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.school_outlined,
                  title: 'Learn the Rails',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EducationScreen()))),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.favorite_outline,
                  title: 'Favorite Routes',
                  onTap: () {}),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.history, title: 'Travel History', onTap: () {}),
              const Divider(height: 1),
              _ActionRow(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {}),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.info_outline,
                title: 'About',
                onTap: () => _showAboutDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await _authService.logout();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfile(BuildContext context) {
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
                Text('Edit Profile', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: handleController,
                  decoration: const InputDecoration(labelText: 'Handle'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bioController,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: colorController,
                  decoration: const InputDecoration(
                      labelText: 'Avatar color (hex, optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: homeController,
                  decoration:
                      const InputDecoration(labelText: 'Home station ID (optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lineController,
                  decoration:
                      const InputDecoration(labelText: 'Favorite line (optional)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allowSearch,
                  onChanged: (v) => setModalState(() => allowSearch = v),
                  title: const Text('Allow others to find me by handle'),
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
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Smart Commuter Assistant+'),
        content: const Text(
          'Smart Commuter Assistant+ v1.0\n\n'
          'Dynamic Navigation & Occupancy Computations.\n\n'
          'An intelligent companion for Malaysian public transport.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
