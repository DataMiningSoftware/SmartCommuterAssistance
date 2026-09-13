import 'package:flutter/material.dart';

import '../screens/education_screen.dart';
import '../services/navigation_state.dart';
import '../services/race_service.dart';
import '../services/social_service.dart';

class PartySheet extends StatefulWidget {
  const PartySheet({super.key});

  @override
  State<PartySheet> createState() => _PartySheetState();
}

class _PartySheetState extends State<PartySheet> {
  final SocialService _social = SocialService.instance;
  final RaceService _race = RaceService.instance;
  final TextEditingController _codeController = TextEditingController();
  final String _targetMode = 'shared_destination';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ValueListenableBuilder(
        valueListenable: _social.currentParty,
        builder: (context, party, _) {
          if (party == null) {
            return _buildNoParty(context);
          }
          return _buildParty(context, party);
        },
      ),
    );
  }

  Widget _buildNoParty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start a party', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Travel with friends and race each other.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final party = await _social.createParty();
              if (context.mounted && party != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Party created. Code: ${party.joinCode}')),
                );
              }
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create party'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Join code',
                    hintText: 'ABC123',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () async {
                  final party =
                      await _social.joinParty(_codeController.text.trim());
                  if (context.mounted && party != null) {
                    setState(() {});
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not join party.')),
                    );
                  }
                },
                child: const Text('Join'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParty(BuildContext context, Party party) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Party', style: Theme.of(context).textTheme.titleLarge),
              ),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Join code: ${party.joinCode}')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    party.joinCode,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: _social.partyMembers,
            builder: (context, members, _) {
              if (members.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('Waiting for riders…')),
                );
              }
              return Column(
                children: members.map((m) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(m.label),
                    subtitle: Text(
                      m.currentStationId ?? 'Station unknown',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _social.leaveParty(party.id),
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _startChallenge(context, party.id),
                  icon: const Icon(Icons.flag_rounded),
                  label: const Text('Start challenge'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              final nav = Navigator.of(context, rootNavigator: true);
              nav.pop();
              nav.push(
                MaterialPageRoute(builder: (_) => const EducationScreen()),
              );
            },
            icon: const Icon(Icons.quiz_outlined),
            label: const Text('Quick trivia round'),
          ),
        ],
      ),
    );
  }

  Future<void> _startChallenge(BuildContext context, String partyId) async {
    final category = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Race category')),
            ListTile(
              title: const Text('Fastest Arrival'),
              onTap: () => Navigator.pop(context, 'fastest'),
            ),
            ListTile(
              title: const Text('Most Comfortable'),
              onTap: () => Navigator.pop(context, 'comfort'),
            ),
            ListTile(
              title: const Text('Most Efficient'),
              onTap: () => Navigator.pop(context, 'efficient'),
            ),
          ],
        ),
      ),
    );
    if (category == null) return;
    final race = await _race.startRace(
      partyId: partyId,
      category: category,
      targetMode: _targetMode,
    );
    if (!context.mounted) return;
    if (race != null) {
      Navigator.pop(context);
      NavigationState.instance.goTo(4);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start race.')),
      );
    }
  }
}

void showPartySheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const PartySheet(),
  );
}
