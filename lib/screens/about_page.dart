import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../main.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          
          // App icon and title
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'Z',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Klill',
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            'Zipline',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              fontFamily: 'Klill',
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'v1.0.0',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontFamily: 'LiberationSans',
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            'Fast and easy file transfer tool for LAN users',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontFamily: 'LiberationSans',
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Device info
          Consumer<AppStateProvider>(
            builder: (context, appState, child) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Name', appState.settings?.buddyName ?? 'Unknown'),
                      _buildInfoRow('Port', appState.settings?.port.toString() ?? '6442'),
                      _buildInfoRow('Platform', 'Windows'),
                      _buildInfoRow('Destination', 
                          (appState.settings?.destPath ?? '').isEmpty
                              ? 'Downloads'
                              : appState.settings!.destPath),
                    ],
                  ),
                ),
              );
            },
          ),
          
          const Spacer(),
          
          // Warning text
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning,
                  color: Colors.orange[700],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Zipline transfers files without encryption. Only use in trusted networks.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[800],
                      fontFamily: 'LiberationSans',
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Copyright
          Text(
            'Zipline - Fast file transfer for LAN users\n© 2025',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontFamily: 'LiberationSans',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'LiberationSans',
              ),
            ),
          ),
        ],
      ),
    );
  }
}