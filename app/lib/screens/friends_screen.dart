import 'package:flutter/material.dart';

import '../services/profile_service.dart';
import '../services/social_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final SocialService _social = SocialService.instance;
  final ProfileService _profile = ProfileService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Friend> _friends = const [];
  List<FriendRequest> _requests = const [];
  List<UserProfile> _searchResults = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final friends = await _social.getFriends();
    final requests = await _social.incomingRequests();
    if (mounted) {
      setState(() {
        _friends = friends;
        _requests = requests;
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final results = await _profile.searchUsers(query);
    if (mounted) setState(() => _searchResults = results);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Search by handle',
                          hintText: 'e.g. @rider88',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _search,
                      child: const Text('Search'),
                    ),
                  ],
                ),
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Results', style: Theme.of(context).textTheme.titleMedium),
                  ..._searchResults.map((p) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline),
                        title: Text(p.handle),
                        subtitle: p.displayName != null ? Text(p.displayName!) : null,
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            await _social.sendRequestToHandle(p.handle);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Request sent to ${p.handle}')),
                              );
                            }
                          },
                          child: const Text('Add'),
                        ),
                      )),
                ],
                const SizedBox(height: 20),
                if (_requests.isNotEmpty) ...[
                  Text('Friend requests',
                      style: Theme.of(context).textTheme.titleLarge),
                  ..._requests.map((r) => ListTile(
                        dense: true,
                        title: Text('Request #${r.id}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await _social.respondToRequest(r.id, true);
                                _load();
                              },
                              child: const Text('Accept'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await _social.respondToRequest(r.id, false);
                                _load();
                              },
                              child: const Text('Decline'),
                            ),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 20),
                Text('Your friends', style: Theme.of(context).textTheme.titleLarge),
                if (_friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No friends yet — go make some.')),
                  )
                else
                  ..._friends.map((f) => ListTile(
                        leading: const Icon(Icons.person_rounded),
                        title: Text(f.label),
                        subtitle: Text('@${f.handle}'),
                      )),
              ],
            ),
    );
  }
}
