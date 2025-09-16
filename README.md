# Zipline

**Fast and easy file transfer tool for LAN users**

Zipline is a modern, cross-platform file transfer application built with Flutter. It enables fast and secure file sharing between devices on the same local network without requiring internet connectivity.

## Features

- **Lightning Fast**: Optimized for high-speed file transfers over local networks
- **Multiple File Types**: Transfer files, folders, and text snippets
- **Network Discovery**: Automatically discover other Zipline instances on your network
- **Secure**: All transfers happen locally - no data leaves your network
- **Cross-Platform**: Works on Windows, macOS, and Linux
- **Modern UI**: Clean, intuitive interface with dark/light theme support
- **Progress Tracking**: Real-time transfer progress and speed monitoring
- **Transfer History**: Keep track of all your file transfers
- **Customizable**: Configurable download directory and network settings

## Screenshots

*Screenshots coming soon...*

## Requirements

### System Requirements
- **Operating System**: Windows 10/11, macOS 10.14+, or Linux (Ubuntu 18.04+)
- **RAM**: 512 MB minimum, 2 GB recommended
- **Storage**: 100 MB free space
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
3. Select a device from the "Buddies" tab to send files
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
- **Default Port**: 7250
- **Protocol**: UDP/TCP
- **Discovery**: Broadcast + Unicast

## Configuration

### Settings
Access settings through the gear icon in the bottom navigation:
- **Download Directory**: Set custom download location
- **Network Port**: Configure listening port (default: 7250)
- **Buddy Name**: Set your display name
- **History Management**: Clear transfer history

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
│   ├── peer.dart            # Network peer model
│   ├── transfer_item.dart   # File transfer item
│   └── transfer_session.dart # Transfer session
├── providers/               # State management
│   └── app_state_provider.dart
├── screens/                 # UI screens
│   ├── main_screen.dart     # Main application screen
│   ├── buddies_page.dart    # Network discovery
│   ├── send_page.dart       # File sending
│   ├── recent_page.dart     # Transfer history
│   ├── settings_page.dart   # Application settings
│   └── about_page.dart      # About information
├── services/                # Business logic
│   ├── file_transfer_service.dart    # File transfer logic
│   ├── peer_discovery_service.dart   # Network discovery
│   └── buddy_message.dart            # Network messaging
└── widgets/                 # Reusable UI components
    ├── buddy_list_item.dart
    ├── tab_bar_widget.dart
    ├── tool_bar_widget.dart
    └── transfer_progress_widget.dart
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

## Acknowledgments

- Built with [Flutter](https://flutter.dev/)
- Inspired by modern file transfer applications
- Thanks to the Flutter community for excellent packages

## Support

- **Email**: support@zipline.app
- **Issues**: [GitHub Issues](https://github.com/yourusername/zipline/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/zipline/discussions)
- **Documentation**: [Wiki](https://github.com/yourusername/zipline/wiki)

## Changelog

### Version 1.0.0
- Initial release
- File and folder transfer support
- Network discovery
- Real-time progress tracking
- Transfer history
- Cross-platform support

---

**Zipline** - Fast file transfer for LAN users © 2025
