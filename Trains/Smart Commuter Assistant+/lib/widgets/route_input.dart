import 'package:flutter/material.dart';

class RouteInput extends StatelessWidget {
  final TextEditingController originController;
  final TextEditingController destinationController;

  const RouteInput({
    super.key,
    required this.originController,
    required this.destinationController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Origin Input
            TextField(
              controller: originController,
              decoration: InputDecoration(
                labelText: 'From',
                hintText: 'Enter origin station',
                prefixIcon: Icon(
                  Icons.radio_button_checked,
                  color: Theme.of(context).colorScheme.primary,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    // TODO: Use current location
                    originController.text = 'Current Location';
                  },
                  icon: const Icon(Icons.my_location),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Swap Button
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {
                    // Swap origin and destination
                    final temp = originController.text;
                    originController.text = destinationController.text;
                    destinationController.text = temp;
                  },
                  icon: const Icon(Icons.swap_vert, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Destination Input
            TextField(
              controller: destinationController,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Enter destination station',
                prefixIcon: Icon(
                  Icons.location_on,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                suffixIcon: PopupMenuButton<String>(
                  onSelected: (value) {
                    destinationController.text = value;
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'KLCC', child: Text('KLCC')),
                    const PopupMenuItem(value: 'Bukit Bintang', child: Text('Bukit Bintang')),
                    const PopupMenuItem(value: 'KL Sentral', child: Text('KL Sentral')),
                    const PopupMenuItem(value: 'Pasar Seni', child: Text('Pasar Seni')),
                    const PopupMenuItem(value: 'Masjid Jamek', child: Text('Masjid Jamek')),
                  ],
                  child: const Icon(Icons.arrow_drop_down),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Search Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Search for routes
                  if (originController.text.isNotEmpty && 
                      destinationController.text.isNotEmpty) {
                    // Simulate route search
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Searching routes from ${originController.text} to ${destinationController.text}...',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.search),
                label: const Text('Find Routes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}