# Zipline Changelog

## v1.0.1 - September 24, 2025

### 🧹 Code Quality & User Experience
- **Removed Auto-Cancel Timeout**: Transfers now wait indefinitely for receiver response instead of timing out after 30 seconds
- **Enhanced Cancel Functionality**: Added proper cancel button for waiting transfers with immediate dialog dismissal
- **Notification System Removal**: Removed intrusive TopNotification system for cleaner, less disruptive user experience
- **Code Cleanup**: Comprehensive removal of debug statements, verbose comments, and development artifacts
- **Action Bar Improvements**: Fixed draggable area functionality with proper double-tap to maximize behavior

### 🔧 Transfer Management
- **Improved Cancellation Flow**: 
  - Sender cancellation immediately hides progress dialog without extra popups
  - Receiver decline automatically dismisses sender's progress dialog
  - Clean state management with proper completer cleanup
- **Better Error Handling**: Simplified error handling with consistent silent failure patterns
- **Transfer Request Enhancements**: Added transfer cancel notification system between sender and receiver

### 🛠️ Technical Improvements
- **Protocol Enhancement**: Added transferCancel message type for proper sender-receiver communication
- **Window Management**: Fixed action bar drag functionality with proper hit testing and gesture handling
- **Code Organization**: Streamlined codebase with removal of unnecessary debug infrastructure
- **Performance**: Eliminated notification overlay system reducing UI complexity and improving responsiveness

---

## v1.0.0 - September 23, 2025

### 🚀 Performance & Speed
- **Transfer Speed Optimization**: 25-40% faster transfers through TCP optimization, reduced artificial delays, and improved buffering
- **Progress Bar Synchronization**: Fixed sender-receiver progress desync with flow control and realistic progress tracking
- **Socket Buffer Management**: Optimized TCP settings with larger buffers and strategic flushing

### 🔧 Network & Discovery
- **Peer Discovery Fix**: Universal interface support for WiFi, Ethernet, Virtual, and Tunnel interfaces
- **Port Change**: Updated default port from 4644 to 6442 for better compatibility
- **WiFi Device Stability**: Fixed frequent disconnections with smart refresh and 3-minute peer timeout
- **Port Conflict Detection**: Enhanced with actual process identification and intelligent suggestions

### 🎨 UI & UX Improvements
- **Dialog UI Alignment**: Fixed button alignment, spacing, and visual hierarchy in port conflict dialogs
- **Transfer Request System**: Complete request/accept flow with custom save locations and peer preferences
- **Progress Tracking**: Synchronized progress bars with 128KB update intervals and boundary protection

### 🛠️ Technical Improvements
- **Code Cleanup**: Removed debug code and unnecessary comments
- **Legacy References**: Cleaned up all legacy references while maintaining compatibility
- **Error Handling**: Enhanced with better timeout management and graceful degradation
- **Cross-Platform**: Improved Windows, Linux, and macOS compatibility

### 📱 User Experience
- **Smart Save Locations**: Remember save preferences per peer for future transfers
- **Better Error Messages**: Application-specific conflict detection and suggestions
- **Responsive UI**: More frequent progress updates with reduced overhead
- **Stable Connections**: Maintained device connections during network fluctuations

---
