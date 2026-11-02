import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/database_health_service.dart';
import '../widgets/app_page_title.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const String supportEmail = 'mnawfalbn@gmail.com';
  static const String privacyUrl =
      'https://dataminingsoftware.github.io/SmartCommuterAssistance/privacy.html';
  static const String deleteAccountUrl =
      'https://dataminingsoftware.github.io/SmartCommuterAssistance/delete-account.html';
  static const String issuesUrl =
      'https://github.com/DataMiningSoftware/SmartCommuterAssistance/issues';

  String _version = '1.0.0';
  String _build = '1';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    } catch (_) {}
  }

  String _connectionLabel(AppLocalizations l10n) {
    return DatabaseHealthService.instance.isConnected.value
        ? l10n.dataLive
        : l10n.dataOffline;
  }

  Future<void> _openEmail() async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final subject = l10n.supportEmailSubject(_version);
    final body = l10n.supportEmailBody(
      _version,
      _build,
      defaultTargetPlatform.name,
      locale,
      _connectionLabel(l10n),
    );
    final uri = Uri.parse(
      'mailto:$supportEmail'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      await _copyEmail(l10n.supportNoMailApp);
    }
  }

  Future<void> _copyEmail([String? message]) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? l10n.supportEmailCopied)),
    );
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final faqs = <(String, String)>[
      (l10n.supportFaqOfflineQuestion, l10n.supportFaqOfflineAnswer),
      (l10n.supportFaqCrowdQuestion, l10n.supportFaqCrowdAnswer),
      (l10n.supportFaqDelayQuestion, l10n.supportFaqDelayAnswer),
      (l10n.supportFaqPrivacyQuestion, l10n.supportFaqPrivacyAnswer),
      (l10n.supportFaqEtaQuestion, l10n.supportFaqEtaAnswer),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: AppPageTitle(
          icon: Icons.support_agent_rounded,
          leadingText: 'Help',
          accentText: 'Desk',
          badgeText: 'SUPPORT',
          subtitle: l10n.supportContactBody,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SupportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mail_outline_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.supportContactTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.supportContactBody,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  supportEmail,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openEmail,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(l10n.supportSendEmailButton),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => _copyEmail(),
                      child: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.supportFaqTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _SupportCard(
            child: Column(
              children: [
                for (var i = 0; i < faqs.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ExpansionTile(
                    title: Text(
                      faqs[i].$1,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(faqs[i].$2, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.supportLinksTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _SupportCard(
            child: Column(
              children: [
                _LinkRow(
                  icon: Icons.privacy_tip_outlined,
                  label: l10n.privacyPolicyTitle,
                  onTap: () => _openUrl(privacyUrl),
                ),
                const Divider(height: 1),
                _LinkRow(
                  icon: Icons.delete_outline_rounded,
                  label: l10n.supportDeleteDataLink,
                  onTap: () => _openUrl(deleteAccountUrl),
                ),
                const Divider(height: 1),
                _LinkRow(
                  icon: Icons.bug_report_outlined,
                  label: l10n.supportIssuesLink,
                  onTap: () => _openUrl(issuesUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  final Widget child;

  const _SupportCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: child,
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: onTap,
    );
  }
}
