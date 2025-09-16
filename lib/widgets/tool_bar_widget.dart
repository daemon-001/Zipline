import 'package:flutter/material.dart';

class ZiplineToolBar extends StatelessWidget {
  final VoidCallback onIpPressed;
  final VoidCallback onSettingsPressed;

  const ZiplineToolBar({
    super.key,
    required this.onIpPressed,
    required this.onSettingsPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildToolButton(
            icon: Icons.router,
            label: 'IP',
            onPressed: onIpPressed,
            context: context,
          ),
          _buildToolButton(
            icon: Icons.settings,
            label: 'Settings',
            onPressed: onSettingsPressed,
            context: context,
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 12,
                fontFamily: 'LiberationSans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}