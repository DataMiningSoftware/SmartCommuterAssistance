import 'package:flutter/material.dart';
import '../widgets/crowd_indicator.dart';

class StationDetails extends StatelessWidget {
  const StationDetails({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KL Sentral Station'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Station Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.train,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KL Sentral',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text('Central Transportation Hub'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Current Crowd Level: '),
                        const CrowdIndicator(level: 'Crowded'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Next Best Time: 2:30 PM',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Upcoming Trains
            const Text(
              'Upcoming Trains',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            _buildTrainCard('Kelana Jaya Line', 'KLCC', '2 min', 'Moderate'),
            _buildTrainCard('Ampang Line', 'Masjid Jamek', '5 min', 'Light'),
            _buildTrainCard('KTM Komuter', 'Seremban', '8 min', 'Crowded'),
            _buildTrainCard('Kelana Jaya Line', 'Gombak', '12 min', 'Light'),

            const SizedBox(height: 20),

            // Weather Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.wb_sunny,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weather: Sunny',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('32°C • Good for commuting'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainCard(
      String line, String destination, String eta, String crowdLevel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.train),
        ),
        title: Text(line),
        subtitle: Text('To $destination'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              eta,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            CrowdIndicator(level: crowdLevel),
          ],
        ),
      ),
    );
  }
}
