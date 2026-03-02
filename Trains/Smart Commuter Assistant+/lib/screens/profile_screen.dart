import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  bool _offlineModeEnabled = false;
  bool _accessibilityEnabled = false;
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _authService.currentUser.value;
    final userName = user?.name ?? 'User';
    final userEmail = user?.email ?? 'no-email@example.com';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2E9F6)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userEmail,
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF4B400), Color(0xFFD7263D)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '1,250 Reward Points',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
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
                value: _accessibilityEnabled,
                onChanged: (v) => setState(() => _accessibilityEnabled = v),
                title: const Text('Accessibility'),
                subtitle: const Text('Larger labels and stronger contrast'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Quick Actions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _Panel(
            children: [
              _ActionRow(icon: Icons.favorite_outline, title: 'Favorite Routes', onTap: () {}),
              const Divider(height: 1),
              _ActionRow(icon: Icons.history, title: 'Travel History', onTap: () {}),
              const Divider(height: 1),
              _ActionRow(icon: Icons.help_outline, title: 'Help & Support', onTap: () {}),
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Smart Commuter+'),
        content: const Text(
          'Smart Commuter Assistant+ v1.0\n\n'
          'An intelligent companion for Malaysian public transport.\n\n'
          'Built for daily commuters.',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E9F6)),
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
