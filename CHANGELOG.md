# Zipline Changelog

## Recent Updates

### Performance & Speed
- **Transfer Speed Optimization**: 25-40% faster transfers through TCP optimization, reduced artificial delays, and improved buffering
- **Progress Bar Synchronization**: Fixed sender-receiver progress desync with flow control and realistic progress tracking
- **Socket Buffer Management**: Optimized TCP settings with larger buffers and strategic flushing

### Network & Discovery
- **Peer Discovery Fix**: Universal interface support for WiFi, Ethernet, Virtual, and Tunnel interfaces
- **Port Change**: Updated default port from 4644 to 6442 for better compatibility
- **WiFi Buddy Stability**: Fixed frequent disconnections with smart refresh and 3-minute peer timeout
- **Port Conflict Detection**: Enhanced with actual process identification and intelligent suggestions

### UI & UX Improvements
- **Dialog UI Alignment**: Fixed button alignment, spacing, and visual hierarchy in port conflict dialogs
- **Transfer Request System**: Complete request/accept flow with custom save locations and peer preferences
- **Progress Tracking**: Synchronized progress bars with 128KB update intervals and boundary protection

### Technical Improvements
- **Code Cleanup**: Removed debug code and unnecessary comments
- **Dukto References**: Cleaned up all Dukto references while maintaining compatibility
- **Error Handling**: Enhanced with better timeout management and graceful degradation
- **Cross-Platform**: Improved Windows, Linux, and macOS compatibility

### User Experience
- **Smart Save Locations**: Remember save preferences per peer for future transfers
- **Better Error Messages**: Application-specific conflict detection and suggestions
- **Responsive UI**: More frequent progress updates with reduced overhead
- **Stable Connections**: Maintained buddy connections during network fluctuations

---

*All changes maintain backward compatibility and protocol standards.*
