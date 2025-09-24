# Zipline

**Fast and easy file transfer tool for LAN users**

Zipline is a modern, cross-platform file transfer application built with Flutter. It enables fast file sharing between devices on the same local network without requiring internet connectivity.

## Visuals
### Home page
<img width="982" height="703" alt="zipline 21-09-2025 09_10_15 PM" src="https://github.com/user-attachments/assets/b4c1b3ac-9023-41c8-aa4c-ccfc89f40af5" />

### Transfer page
<img width="982" height="703" alt="zipline 21-09-2025 09_10_23 PM" src="https://github.com/user-attachments/assets/70059fca-9c25-4a21-a7ef-646ca92277ae" />

### Progress bar
<img width="982" height="703" alt="zipline 21-09-2025 09_10_42 PM" src="https://github.com/user-attachments/assets/1f92f6cf-2d07-47a5-86b1-4e5f26e9efe4" />



## Features

- **Lightning Fast**: Optimized for high-speed file transfers over local networks
- **Multiple File Types**: Transfer files, folders, and text snippets
- **Network Discovery**: Automatically discover other Zipline instances on your network
- **Secure**: All transfers happen locally - no data leaves your network
- **Cross-Platform**: Works on Windows, macOS, and Linux
- **Modern UI**: Clean, intuitive interface with emoji-based icons
- **Progress Tracking**: Real-time transfer progress and speed monitoring
- **Transfer History**: Keep track of all your file transfers
- **Customizable**: Configurable download directory and network settings
- **Lightweight**: No external assets - uses system fonts and emoji icons


## Requirements

### System Requirements
- **Operating System**: Windows 10/11, Android, macOS 10.14+, or Linux (Ubuntu 18.04+)
- **RAM**: 256 MB minimum, 1 GB recommended
- **Storage**: 50 MB free space (lightweight, no external assets)
- **Network**: Local area network (LAN) connection - WiFi or Ethernet

### Development Requirements
- **Flutter SDK**: 3.9.2 or higher
- **Dart SDK**: 3.9.2 or higher
- **Git**: For version control
- **IDE**: VS Code, Android Studio, or IntelliJ IDEA (recommended)

## Installation

### Pre-built Binaries
Download the latest release from the [Releases](https://github.com/yourusername/zipline/releases) page and install according to your operating system.

### From Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/zipline.git
   cd zipline
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Build the application**
   ```bash
   # For Windows
   flutter build windows
   
   # For macOS
   flutter build macos
   
   # For Linux
   flutter build linux
   ```

4. **Run the application**
   ```bash
   flutter run
   ```

## Usage

### Getting Started
1. Launch Zipline on your device
2. The application will automatically discover other Zipline instances on your network
3. Select a device from the "Devices" tab to send files
4. Choose files or folders to transfer
5. Monitor progress in real-time

### Sending Files
- **Single File**: Click "Send" and select a file
- **Multiple Files**: Select multiple files using Ctrl+Click
- **Folders**: Select entire folders for bulk transfer
- **Text**: Send text snippets directly

### Receiving Files
- Files are automatically saved to your configured download directory
- Default location: `Downloads/Zipline/`
- Customize the download path in Settings

### Network Settings
- **Default Port**: 6442 (configurable)
- **Protocol**: UDP/TCP
- **Discovery**: Broadcast + Unicast
- **Icons**: Emoji-based platform and file type indicators

## Configuration

### Settings
Access settings through the gear icon in the bottom navigation:
- **Download Directory**: Set custom download location
- **Network Port**: Configure listening port (default: 6442)
- **Device Name**: Set your display name
- **History Management**: Clear transfer history
- **Network Diagnostics**: Test network connectivity and configuration

### Network Troubleshooting
- Ensure all devices are on the same network
- Check firewall settings allow Zipline through
- Try different ports if discovery fails
- Restart the application if connections fail

## Development

### Project Structure
```
lib/
├── main.dart                 # Application entry point
├── models/                   # Data models
│   ├── app_settings.dart    # Application settings
│   ├── peer.dart            # Network peer model (emoji icons)
│   ├── transfer_item.dart   # File transfer item (emoji icons)
│   └── transfer_session.dart # Transfer session
├── providers/               # State management
│   └── app_state_provider.dart
├── screens/                 # UI screens
│   ├── main_screen.dart     # Main application screen
│   ├── devices_page.dart    # Network discovery
│   ├── send_page.dart       # File sending
│   ├── recent_page.dart     # Transfer history
│   ├── progress_page.dart   # Transfer progress
│   ├── settings_page.dart   # Application settings
│   ├── about_page.dart      # About information
│   └── ip_page.dart         # IP address display
├── services/                # Business logic
│   ├── file_transfer_service.dart    # File transfer logic
│   ├── peer_discovery_service.dart   # Network discovery
│   ├── device_message.dart            # Network messaging
│   ├── network_utility.dart         # Network utilities
│   ├── progress_dialog_manager.dart # Progress dialog management
│   ├── avatar_web_server.dart       # Avatar web server
│   ├── profile_image_service.dart   # Profile image handling
│   └── save_location_service.dart   # Save location management
├── widgets/                 # Reusable UI components
│   ├── device_list_item.dart
│   ├── tab_bar_widget.dart
│   ├── tool_bar_widget.dart
│   ├── transfer_progress_widget.dart
│   ├── transfer_progress_dialog.dart
│   ├── transfer_request_dialog.dart
│   ├── top_notification.dart
│   ├── user_profile_bar.dart
│   ├── windows_action_bar.dart
│   └── network_warning_dialog.dart
└── utils/                   # Utility functions
    ├── system_info.dart     # System information utilities
    └── speed_calculator.dart # Transfer speed calculations
```

### Building
```bash
# Clean build
flutter clean
flutter pub get

# Build for Windows
flutter build windows

# Build for macOS
flutter build macos

# Build for Linux
flutter build linux
```

### Testing
```bash
# Run tests
flutter test

# Run integration tests
flutter test integration_test/
```

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Technical Details

### Architecture
- **Framework**: Flutter 3.9.2+ with Dart 3.9.2+
- **State Management**: Provider pattern
- **UI**: Material Design 3 with emoji-based icons
- **Networking**: Custom UDP/TCP implementation for peer discovery and file transfer
- **Platform Support**: Windows, macOS, Linux

### Key Features
- **Asset-Free Design**: Uses emoji icons instead of external image assets
- **Efficient Networking**: Optimized peer discovery and file transfer protocols
- **Cross-Platform**: Single codebase for all supported platforms
- **Modern UI**: Clean, responsive interface with system font integration
- **Device Discovery**: Automatic network device detection and management
- **Secure Transfers**: Local network only, no cloud dependencies


## Support

- **Email**: nitesh.kumar4work@gmail.com
- **Issues**: [GitHub Issues](https://github.com/daemon-001/zipline/issues)
- **Discussions**: [GitHub Discussions](https://github.com/daemon-001/zipline/discussions)
- **Documentation**: [Wiki](https://github.com/daemon-001/zipline/wiki)


---

**Zipline** - Fast file transfer for LAN users
