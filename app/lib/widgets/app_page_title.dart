import 'package:flutter/material.dart';

import '../services/database_health_service.dart';

class AppPageTitle extends StatelessWidget {
  final IconData icon;
  final String leadingText;
  final String accentText;
  final String? badgeText;
  final Widget? badge;
  final String? subtitle;
  final Color? accentColor;

  const AppPageTitle({
    super.key,
    required this.icon,
    required this.leadingText,
    required this.accentText,
    this.badgeText,
    this.badge,
    this.subtitle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = accentColor ?? theme.colorScheme.primary;
    final titleStyle = theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ) ??
        const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
        );

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                highlight.withValues(alpha: 0.18),
                highlight.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: highlight.withValues(alpha: 0.18)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12101828),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: highlight, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$leadingText ',
                      style: titleStyle.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    TextSpan(
                      text: accentText,
                      style: titleStyle.copyWith(
                        fontWeight: FontWeight.w900,
                        color: highlight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              if (badge != null || badgeText != null || subtitle != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (badge != null)
                      badge!
                    else if (badgeText != null)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: highlight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeText!,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.62),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ConnectionStatusBadge extends StatelessWidget {
  const ConnectionStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DatabaseHealthService.instance.isConnected,
      builder: (context, connected, _) {
        final color = connected ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
        final label = connected ? 'LIVE' : 'OFFLINE';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          ),
          child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}
