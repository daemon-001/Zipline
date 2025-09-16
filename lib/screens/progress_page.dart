import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/file_transfer_service.dart';
import '../widgets/transfer_progress_widget.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FileTransferService>(
      builder: (context, fileTransferService, child) {
        final activeSessions = fileTransferService.activeSessions;
        
        if (activeSessions.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No Active Transfers',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Klill',
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'File transfers will appear here when in progress',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontFamily: 'LiberationSans',
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Active Transfers',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    fontFamily: 'Klill',
                  ),
                ),
              ),
              ...activeSessions.entries.map((entry) => TransferProgressWidget(
                session: entry.value,
                onCancel: () {
                  fileTransferService.cancelTransfer(entry.key);
                },
              )).toList(),
            ],
          ),
        );
      },
    );
  }
}