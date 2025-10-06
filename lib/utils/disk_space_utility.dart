import 'dart:io';
import 'dart:convert';
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
      
      // Try to get actual available space using platform-specific methods
      final actualSpace = await getAccurateAvailableSpace(dirPath);
      if (actualSpace > 0) {
        return actualSpace;
      }
      
      // Fallback: Test file creation to verify write access
      final tempFile = File(path.join(dirPath, '.zipline_space_test_${DateTime.now().millisecondsSinceEpoch}'));
      
      try {
        // Try to create a small test file
        await tempFile.create();
        
        // Clean up the test file
        await tempFile.delete();
        
        // If we can write but couldn't get actual space, return a large value
        // This indicates space is likely available but we can't determine exact amount
        return 100 * 1024 * 1024 * 1024; // 100GB as fallback
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
      } else if (Platform.isLinux || Platform.isMacOS) {
        // Unix-like systems (Linux, macOS)
        return await _getUnixAvailableSpace(filePath);
      }
      
      // For other platforms, return 0 to indicate we can't determine
      return 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// Windows-specific space checking using wmic command
  static Future<int> _getWindowsAvailableSpace(String filePath) async {
    try {
      // Get the drive letter from the path
      final dir = Directory(filePath);
      if (!await dir.exists()) {
        return 0;
      }
      
      // Extract drive letter (e.g., "C:" from "C:\Users\...")
      String driveLetter;
      if (filePath.length >= 2 && filePath[1] == ':') {
        driveLetter = filePath.substring(0, 2);
      } else {
        // If we can't determine drive letter, try to resolve the path
        final resolvedPath = path.absolute(filePath);
        if (resolvedPath.length >= 2 && resolvedPath[1] == ':') {
          driveLetter = resolvedPath.substring(0, 2);
        } else {
          return 0;
        }
      }
      
      // Use wmic to get disk space information
      final result = await Process.run('wmic', [
        'logicaldisk',
        'where',
        'caption="$driveLetter"',
        'get',
        'freespace',
        '/format:csv'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        
        // Parse the CSV output to find the FreeSpace value
        for (final line in lines) {
          if (line.contains('FreeSpace') || line.trim().isEmpty) continue;
          
          final parts = line.split(',');
          if (parts.length >= 2) {
            final freeSpaceStr = parts[1].trim();
            if (freeSpaceStr.isNotEmpty && RegExp(r'^\d+$').hasMatch(freeSpaceStr)) {
              return int.parse(freeSpaceStr);
            }
          }
        }
      }
      
      // Fallback: Try PowerShell method
      return await _getWindowsAvailableSpacePowerShell(driveLetter);
    } catch (e) {
      return 0;
    }
  }
  
  /// Fallback Windows method using PowerShell
  static Future<int> _getWindowsAvailableSpacePowerShell(String driveLetter) async {
    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-WmiObject -Class Win32_LogicalDisk -Filter "Caption=\'$driveLetter\'" | Select-Object -ExpandProperty FreeSpace'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && RegExp(r'^\d+$').hasMatch(output)) {
          return int.parse(output);
        }
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// Unix-like systems (Linux, macOS) space checking using df command
  static Future<int> _getUnixAvailableSpace(String filePath) async {
    try {
      final dir = Directory(filePath);
      if (!await dir.exists()) {
        return 0;
      }
      
      // Use df command to get disk space information
      final result = await Process.run('df', ['-B1', filePath]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        
        // Parse df output (format: Filesystem 1B-blocks Used Available Use% Mounted on)
        if (lines.length >= 2) {
          final dataLine = lines[1];
          final parts = dataLine.split(RegExp(r'\s+'));
          
          // Available space is typically the 4th column (index 3)
          if (parts.length >= 4) {
            final availableStr = parts[3];
            if (RegExp(r'^\d+$').hasMatch(availableStr)) {
              return int.parse(availableStr);
            }
          }
        }
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }
}
