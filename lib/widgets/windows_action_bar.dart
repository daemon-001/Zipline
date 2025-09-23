import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowsActionBar extends StatefulWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;

  const WindowsActionBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
  });

  @override
  State<WindowsActionBar> createState() => _WindowsActionBarState();
}

class _WindowsActionBarState extends State<WindowsActionBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _checkMaximized() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = isMaximized;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  Future<void> _minimizeWindow() async {
    await windowManager.minimize();
  }

  Future<void> _maximizeWindow() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _closeWindow() async {
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF2D2D30) 
            : const Color(0xFFF3F3F3),
        border: Border(
          bottom: BorderSide(
            color: isDark 
                ? const Color(0xFF3E3E42) 
                : const Color(0xFFE1E1E1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Extended drag area for moving window - covers most of the action bar
          Expanded(
            child: GestureDetector(
              onPanStart: (details) {
                windowManager.startDragging();
              },
              onTap: () {
                // Double tap to maximize/restore
                _maximizeWindow();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // App icon
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/icon.png'),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'LiberationSans',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Add some spacing before window controls
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
          ),
          // Window controls
          Row(
            children: [
              // Minimize button
              _buildWindowButton(
                icon: Icons.remove,
                onPressed: _minimizeWindow,
                isDark: isDark,
              ),
              // Maximize/Restore button
              _buildWindowButton(
                icon: _isMaximized ? Icons.fullscreen_exit : Icons.fullscreen,
                onPressed: _maximizeWindow,
                isDark: isDark,
              ),
              // Close button
              _buildWindowButton(
                icon: Icons.close,
                onPressed: _closeWindow,
                isDark: isDark,
                isClose: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDark,
    bool isClose = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: isClose 
            ? (isDark ? Colors.red.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.1))
            : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
        child: Container(
          width: 48,
          height: 36,
          child: Icon(
            icon,
            size: 16,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
