import 'package:flutter/material.dart';

import '../models/transit_graph.dart';
import '../models/trivia_question.dart';
import '../services/education_service.dart';
import '../services/transit_data_service.dart';
import '../widgets/app_page_title.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.school_rounded,
          leadingText: 'Learn',
          accentText: 'The Rails',
          badgeText: 'EDUCATION',
          subtitle: 'Station lore & trivia',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Lore'), Tab(text: 'Trivia')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [LoreTab(), TriviaTab()],
      ),
    );
  }
}

class LoreTab extends StatefulWidget {
  const LoreTab({super.key});

  @override
  State<LoreTab> createState() => _LoreTabState();
}

class _LoreTabState extends State<LoreTab> {
  final EducationService _education = EducationService.instance;
  List<StationLore> _lore = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lore = await _education.fetchLore();
    if (mounted) {
      setState(() {
        _lore = lore;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_lore.isEmpty) {
      return const Center(child: Text('No station lore yet.'));
    }
    return ListView.builder(
      itemCount: _lore.length,
      itemBuilder: (context, index) {
        final lore = _lore[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ExpansionTile(
            leading: const Icon(Icons.location_city),
            title: Text(lore.stationName),
            subtitle: Text(
              lore.openingYear != null ? 'Opened ${lore.openingYear}' : '',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...lore.facts.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $f'),
                        )),
                    if (lore.context != null) ...[
                      const SizedBox(height: 8),
                      Text(lore.context!,
                          style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                    if (lore.sourceName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Source: ${lore.sourceName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TriviaTab extends StatefulWidget {
  const TriviaTab({super.key});

  @override
  State<TriviaTab> createState() => _TriviaTabState();
}

class _TriviaTabState extends State<TriviaTab> {
  final EducationService _education = EducationService.instance;
  final TriviaGenerator _generator = TriviaGenerator();

  TransitGraph? _graph;
  TriviaQuestion? _question;
  MasteryStats? _mastery;
  bool _answered = false;
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final graph = await TransitDataService.instance.load();
    final mastery = await _education.getMasteryStats();
    if (mounted) {
      setState(() {
        _graph = graph;
        _mastery = mastery;
        _question = _generator.generate(graph);
      });
    }
  }

  void _answer(int index) async {
    if (_answered || _question == null) return;
    setState(() {
      _answered = true;
      _selectedIndex = index;
    });
    final q = _question!;
    final correct = index == q.correctIndex;
    await _education.recordQuizAttempt(
      kind: q.kind,
      stationId: q.stationId,
      correct: correct,
    );
  }

  void _next() {
    if (_graph == null) return;
    setState(() {
      _question = _generator.generate(_graph!);
      _answered = false;
      _selectedIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_graph == null || _question == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final q = _question!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_mastery != null) ...[
          _MasteryCard(stats: _mastery!),
          const SizedBox(height: 16),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.prompt,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                ...List.generate(q.options.length, (i) {
                  final isCorrect = i == q.correctIndex;
                  final isSelected = _answered && (i == _selectedIndex);
                  final show = _answered && (isCorrect || isSelected);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.tonal(
                      onPressed: _answered ? null : () => _answer(i),
                      style: FilledButton.styleFrom(
                        backgroundColor: show
                            ? (isCorrect ? Colors.green : Colors.red)
                            : null,
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(q.options[i]),
                    ),
                  );
                }),
                if (_answered) ...[
                  const SizedBox(height: 8),
                  Text(q.explanation,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _next, child: const Text('Next')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _MasteryCard extends StatelessWidget {
  final MasteryStats stats;

  const _MasteryCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'Stations learned', value: '${stats.stationsLearned}'),
          _Stat(label: 'Accuracy', value: '${stats.accuracyPct}%'),
          _Stat(label: 'No-hint correct', value: '${stats.noHintCorrect}'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
