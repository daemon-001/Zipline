import 'package:flutter/material.dart';

class NetworkWarningDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? suggestion;
  final VoidCallback? onRetry;
  final VoidCallback? onChangePort;
  final VoidCallback? onContinue;
  final bool canRetry;
  final bool canChangePort;
  final bool canContinue;

  const NetworkWarningDialog({
    Key? key,
    required this.title,
    required this.message,
    this.suggestion,
    this.onRetry,
    this.onChangePort,
    this.onContinue,
    this.canRetry = false,
    this.canChangePort = false,
    this.canContinue = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 14),
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.blue.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (canContinue)
          TextButton(
            onPressed: onContinue,
            child: const Text('Continue Anyway'),
          ),
        if (canChangePort)
          TextButton(
            onPressed: onChangePort,
            child: const Text('Change Port'),
          ),
        if (canRetry)
          FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        if (!canRetry && !canChangePort && !canContinue)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
      ],
    );
  }

  /// Show port conflict warning dialog
  static Future<String?> showPortConflictDialog({
    required BuildContext context,
    required int port,
    String? conflictingApp,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => NetworkWarningDialog(
        title: 'Port Conflict Detected',
        message: conflictingApp != null
            ? 'Port $port is already being used by "$conflictingApp".\n\nZipline cannot start the file transfer service on this port.'
            : 'Port $port is already in use by another application.\n\nZipline cannot start the file transfer service on this port.',
        suggestion: 'Try changing the port in settings or close the conflicting application.',
        canRetry: true,
        canChangePort: true,
        onRetry: () => Navigator.of(context).pop('retry'),
        onChangePort: () => Navigator.of(context).pop('change_port'),
      ),
    );
    return result;
  }

  /// Show network interface warning dialog
  static Future<void> showNetworkInterfaceDialog({
    required BuildContext context,
    required List<String> interfaces,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => NetworkWarningDialog(
        title: 'Multiple Network Connections',
        message: 'Your device has multiple active network connections:\n\n${interfaces.join('\n')}',
        suggestion: 'Other devices will see separate entries for each connection. You can use any of them to transfer files.',
        canContinue: true,
        onContinue: () => Navigator.of(context).pop(),
      ),
    );
  }

  /// Show general network error dialog
  static Future<bool?> showNetworkErrorDialog({
    required BuildContext context,
    required String error,
    String? suggestion,
    bool canRetry = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => NetworkWarningDialog(
        title: 'Network Error',
        message: error,
        suggestion: suggestion,
        canRetry: canRetry,
        canContinue: !canRetry,
        onRetry: canRetry ? () => Navigator.of(context).pop(true) : null,
        onContinue: !canRetry ? () => Navigator.of(context).pop(false) : null,
      ),
    );
    return result;
  }
}