import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/file_transfer_service.dart';
import '../models/transfer_session.dart';
import '../widgets/transfer_progress_widget.dart';
import '../models/transfer_item.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<FileTransferService>(
      builder: (context, fileTransfer, child) {
        // Get all completed, failed, or cancelled sessions from both active and completed
        final allSessions = [
          ...fileTransfer.activeSessions.values,
          ...fileTransfer.completedSessions.values,
        ];
        
        final completedSessions = allSessions
            .where((session) => 
                session.status == TransferStatus.completed ||
                session.status == TransferStatus.failed ||
                session.status == TransferStatus.cancelled)
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt)); // Most recent first

        if (completedSessions.isEmpty) {
          final theme = Theme.of(context);
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 64,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Recent Transfers',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Klill',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your recent file transfers will appear here',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontFamily: 'LiberationSans',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: completedSessions.length,
          itemBuilder: (context, index) {
            final session = completedSessions[index];
            return TransferProgressWidget(session: session);
          },
        );
      },
    );
  }
}