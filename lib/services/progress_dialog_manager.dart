import 'package:flutter/material.dart';
import '../models/transfer_session.dart';
import '../widgets/transfer_progress_dialog.dart';

class ProgressDialogManager {
  static ProgressDialogManager? _instance;
  static ProgressDialogManager get instance => _instance ??= ProgressDialogManager._();
  
  ProgressDialogManager._();

  OverlayEntry? _overlayEntry;
  TransferSession? _currentSession;
  VoidCallback? _onCancel;

  bool get isShowing => _overlayEntry != null;

  void showProgress(BuildContext context, TransferSession session, {VoidCallback? onCancel}) {
    // Don't show multiple dialogs
    if (_overlayEntry != null) {
      updateProgress(session);
      return;
    }

    _currentSession = session;
    _onCancel = onCancel;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => _buildProgressOverlay(),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildProgressOverlay() {
    if (_currentSession == null) return const SizedBox.shrink();
    
    return Material(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: TransferProgressDialog(
          session: _currentSession!,
          onCancel: _onCancel,
        ),
      ),
    );
  }

  void updateProgress(TransferSession session) {
    if (_overlayEntry == null) return;
    
    _currentSession = session;
    _overlayEntry!.markNeedsBuild();
  }

  void hideProgress() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _currentSession = null;
      _onCancel = null;
    }
  }

  void hideProgressWithDelay({Duration delay = const Duration(seconds: 2)}) {
    if (_overlayEntry != null && _currentSession != null) {
      // Show completed state briefly before hiding
      Future.delayed(delay, () {
        hideProgress();
      });
    }
  }
}