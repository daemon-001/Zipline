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
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      backgroundColor: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.3),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
              theme.colorScheme.tertiaryContainer.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.tertiary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Klill',
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontFamily: 'LiberationSans',
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion!,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'LiberationSans',
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
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
          OutlinedButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Continue Anyway'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        if (canChangePort)
          OutlinedButton.icon(
            onPressed: onChangePort,
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Change Port'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        if (canRetry)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        if (!canRetry && !canChangePort && !canContinue)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('OK'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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