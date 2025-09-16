import 'package:flutter/material.dart';

class ZiplineTabBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabChanged;

  const ZiplineTabBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey, width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildTab('Buddies', 0, context),
          _buildTab('Recent', 1, context),
          _buildTab('About', 2, context),
        ],
      ),
    );
  }

  Widget _buildTab(String title, int index, BuildContext context) {
    final isActive = currentIndex == index;
    final theme = Theme.of(context);
    
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isActive ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isActive ? theme.colorScheme.primary : Colors.grey[600],
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
                fontFamily: 'Klill',
              ),
            ),
          ),
        ),
      ),
    );
  }
}