import 'package:flutter/material.dart';

import '../services/race_service.dart';
import '../widgets/app_page_title.dart';
import '../widgets/party_sheet.dart';

class RaceScreen extends StatefulWidget {
  const RaceScreen({super.key});

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  final RaceService _race = RaceService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.emoji_events_rounded,
          leadingText: 'Race',
          accentText: 'Arena',
          badgeText: 'COMPETE',
          subtitle: 'Party races & beat-the-agent',
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: _race.currentRace,
        builder: (context, race, _) {
          if (race == null) {
            return _buildEmpty(context);
          }
          return _buildRace(context, race);
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No race in progress',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start or join a party, then launch a challenge from the party popup.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => showPartySheet(context),
              icon: const Icon(Icons.group_add),
              label: const Text('Open party'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRace(BuildContext context, RaceInfo race) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_categoryLabel(race.category)} — ${race.targetMode == 'shared_destination' ? 'meet-up' : 'race home'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text('Status: ${race.status}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Leaderboard', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: _race.participants,
          builder: (context, participants, _) {
            final sorted = List<RaceParticipant>.from(participants)
              ..sort((a, b) {
                if (a.rank != null && b.rank != null) {
                  return a.rank!.compareTo(b.rank!);
                }
                if (a.rank != null) return -1;
                if (b.rank != null) return 1;
                return a.label.compareTo(b.label);
              });
            if (sorted.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No participants yet.')),
              );
            }
            return Column(
              children: sorted.map((p) {
                final isMe = p.userId == _race.userId;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(
                      p.rank != null ? '${p.rank}' : '·',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  title: Text(isMe ? '${p.label} (you)' : p.label),
                  subtitle: Text(
                    p.status == 'finished'
                        ? 'Finished${p.resultValue != null ? ' — ${_formatResult(race, p.resultValue!)}' : ''}'
                        : 'Racing (${p.routeSource})',
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        Text('Checkpoints', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: _race.checkpoints,
          builder: (context, checkpoints, _) {
            if (checkpoints.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No checkpoints recorded yet.')),
              );
            }
            return Column(
              children: checkpoints.map((c) {
                return ListTile(
                  dense: true,
                  leading: Icon(
                    c.isDisputed ? Icons.warning_amber : Icons.check_circle,
                    color: c.isDisputed ? Colors.orange : Colors.green,
                  ),
                  title: Text(c.stationId),
                  subtitle: Text('#${c.seq}${c.isDisputed ? ' — disputed' : ''}'),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'comfort':
        return 'Most Comfortable';
      case 'efficient':
        return 'Most Efficient';
      default:
        return 'Fastest Arrival';
    }
  }

  String _formatResult(RaceInfo race, double value) {
    switch (race.category) {
      case 'comfort':
        return 'avg crowd $value';
      case 'efficient':
        return '${value.toInt()} transfers';
      default:
        return '$value min';
    }
  }
}
