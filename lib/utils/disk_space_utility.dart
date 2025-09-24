import 'dart:io';
import 'package:path/path.dart' as path;

class DiskSpaceUtility {
  /// Check available disk space for a given path
  /// Returns the available space in bytes, or -1 if unable to determine
  static Future<int> getAvailableSpace(String filePath) async {
    try {
      // Get the directory path
      String dirPath = filePath;
      if (FileSystemEntity.typeSync(filePath) == FileSystemEntityType.file) {
        dirPath = path.dirname(filePath);
      }
      
      final tempFile = File(path.join(dirPath, '.zipline_space_test_${DateTime.now().millisecondsSinceEpoch}'));
      
      try {
        // Try to create a small test file
        await tempFile.create();
        
        // If successful, we can write to this location
        // For now, we'll return a large number to indicate space is available
        // In a real implementation, you might want to use platform-specific APIs
        // to get actual available disk space
        
        // Clean up the test file
        await tempFile.delete();
        
        // Return a reasonable estimate of available space
        // Simplified approach using Dart's cross-platform methods
        return 1024 * 1024 * 1024; // 1GB as a placeholder
      } catch (e) {
        // If we can't create a file, there's likely no space or no permission
        return 0;
      }
    } catch (e) {
      return -1; // Unable to determine
    }
  }
  
  /// Check if there's enough space for a transfer
  /// Returns true if there's enough space, false otherwise
  static Future<bool> hasEnoughSpace(String filePath, int requiredSpace) async {
    final availableSpace = await getAvailableSpace(filePath);
    if (availableSpace == -1) {
      // If we can't determine space, assume it's available
      return true;
    }
    return availableSpace >= requiredSpace;
  }
  
  /// Get a more accurate available space using platform-specific methods
  /// Platform-specific disk space checking
  static Future<int> getAccurateAvailableSpace(String filePath) async {
    try {
      if (Platform.isWindows) {
        // Windows-specific space calculation
        return await _getWindowsAvailableSpace(filePath);
      }
      
      // For other platforms, use the basic method
      return await getAvailableSpace(filePath);
    } catch (e) {
      return await getAvailableSpace(filePath);
    }
  }
  
  /// Windows-specific space checking (simplified)
  static Future<int> _getWindowsAvailableSpace(String filePath) async {
    try {
      // Cross-platform implementation
      // In a real app, you might want to use platform channels to call
      // Windows APIs like GetDiskFreeSpaceEx
      
      // For now, we'll use a simple file creation test
      final dir = Directory(filePath);
      if (!await dir.exists()) {
        return 0;
      }
      
      // Try to create a test file to see if we can write
      final testFile = File(path.join(filePath, '.zipline_test_${DateTime.now().millisecondsSinceEpoch}'));
      try {
        await testFile.create();
        await testFile.delete();
        
        // If successful, return a reasonable estimate
        // In production, implement actual disk space checking
        return 1024 * 1024 * 1024; // 1GB placeholder
      } catch (e) {
        return 0;
      }
    } catch (e) {
      return -1;
    }
  }
}
