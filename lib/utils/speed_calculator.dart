import 'dart:collection';
import 'dart:math';

/// A utility class for calculating accurate transfer speeds with optimized performance
class SpeedCalculator {
  // Optimized speed calculation constants for high performance
  static const int _maxSpeedSamples = 12; // More samples for better accuracy
  static const int _minTimeForSpeedMs = 200; // Faster initial response
  static const int _speedUpdateIntervalMs = 100; // More frequent updates for high-speed transfers
  static const int _outlierThresholdPercent = 200; // Stricter outlier removal
  static const double _smoothingFactor = 0.8; // Better smoothing for high-speed transfers
  
  final Queue<SpeedSample> _speedSamples = Queue<SpeedSample>();
  DateTime? _lastSpeedUpdate;
  int _lastTransferredBytes = 0;
  double _smoothedSpeed = 0.0;
  DateTime? _transferStartTime;
  bool _isHighThroughputMode = false;

  /// Record a new progress update with optimized performance
  void recordProgress(int transferredBytes, DateTime timestamp) {
    // Initialize transfer start time on first call
    _transferStartTime ??= timestamp;
    
    // Detect high-throughput mode (>10MB/s average over first few seconds)
    if (!_isHighThroughputMode && _transferStartTime != null) {
      final elapsed = timestamp.difference(_transferStartTime!);
      if (elapsed.inSeconds >= 2 && transferredBytes > 20 * 1024 * 1024) {
        _isHighThroughputMode = true;
      }
    }
    
    // Adjust update frequency based on throughput
    final updateInterval = _isHighThroughputMode ? 
      _speedUpdateIntervalMs ~/ 2 : _speedUpdateIntervalMs;
    
    // Don't calculate speed too frequently to avoid noise
    if (_lastSpeedUpdate != null && 
        timestamp.difference(_lastSpeedUpdate!).inMilliseconds < updateInterval) {
      return;
    }

    if (_lastSpeedUpdate != null && _lastTransferredBytes > 0) {
      final timeDiff = timestamp.difference(_lastSpeedUpdate!);
      final bytesDiff = transferredBytes - _lastTransferredBytes;
      
      if (timeDiff.inMilliseconds > 0 && bytesDiff > 0) {
        final speed = (bytesDiff * 1000) / timeDiff.inMilliseconds; // bytes per second
        
        // Apply exponential smoothing for more stable readings
        if (_smoothedSpeed == 0.0) {
          _smoothedSpeed = speed;
        } else {
          _smoothedSpeed = (_smoothingFactor * speed) + ((1.0 - _smoothingFactor) * _smoothedSpeed);
        }
        
        _addSpeedSample(SpeedSample(timestamp, speed, _smoothedSpeed));
      }
    } else {
      // First progress update - initialize smoothed speed
      _smoothedSpeed = 0.0;
    }

    _lastSpeedUpdate = timestamp;
    _lastTransferredBytes = transferredBytes;
  }

  void _addSpeedSample(SpeedSample sample) {
    _speedSamples.addLast(sample);
    
    // Remove old samples to maintain rolling window
    while (_speedSamples.length > _maxSpeedSamples) {
      _speedSamples.removeFirst();
    }
    
    // Remove samples older than 5 seconds (shorter than before for faster response)
    final cutoff = DateTime.now().subtract(const Duration(seconds: 5));
    while (_speedSamples.isNotEmpty && _speedSamples.first.timestamp.isBefore(cutoff)) {
      _speedSamples.removeFirst();
    }
    
    // Remove outliers that are too different from the smoothed average
    if (_speedSamples.length >= 3) {
      _removeOutliers();
    }
  }
  
  void _removeOutliers() {
    if (_speedSamples.length < 3) return;
    
    // Calculate average of recent samples
    final recentSamples = _speedSamples.toList().take(5);
    final avgSpeed = recentSamples.map((s) => s.speed).reduce((a, b) => a + b) / recentSamples.length;
    
    // Remove samples that are too far from average
    final threshold = avgSpeed * (_outlierThresholdPercent / 100);
    _speedSamples.removeWhere((sample) => 
      (sample.speed - avgSpeed).abs() > threshold
    );
  }

  /// Get current speed in bytes per second with optimized calculation
  double getCurrentSpeed(DateTime transferStartTime) {
    // Use shorter minimum time for faster response
    final timeSinceStart = DateTime.now().difference(transferStartTime);
    if (timeSinceStart.inMilliseconds < _minTimeForSpeedMs) {
      return 0.0;
    }

    if (_speedSamples.isEmpty) {
      return 0.0;
    }

    // For high-throughput mode, prioritize recent samples
    if (_isHighThroughputMode) {
      return _calculateHighThroughputSpeed();
    }

    // Use exponential smoothing result for stability
    return _smoothedSpeed;
  }
  
  double _calculateHighThroughputSpeed() {
    if (_speedSamples.isEmpty) return 0.0;
    
    // In high-throughput mode, use weighted average with heavy bias toward recent samples
    double totalWeight = 0.0;
    double weightedSum = 0.0;
    
    final samples = _speedSamples.toList();
    for (int i = 0; i < samples.length; i++) {
      // Exponentially increase weight for newer samples
      final weight = pow(2.0, i).toDouble();
      final sample = samples[i];
      weightedSum += sample.smoothedSpeed * weight;
      totalWeight += weight;
    }

    return totalWeight > 0 ? weightedSum / totalWeight : 0.0;
  }

  /// Get instantaneous speed (last smoothed sample) in bytes per second
  double getInstantaneousSpeed() {
    return _speedSamples.isEmpty ? 0.0 : _speedSamples.last.smoothedSpeed;
  }
  
  /// Get peak speed achieved during transfer
  double getPeakSpeed() {
    if (_speedSamples.isEmpty) return 0.0;
    return _speedSamples.map((s) => s.speed).reduce(max);
  }
  
  /// Get average speed over entire transfer
  double getAverageSpeed(DateTime transferStartTime) {
    final elapsed = DateTime.now().difference(transferStartTime);
    if (elapsed.inMilliseconds == 0 || _lastTransferredBytes == 0) return 0.0;
    return (_lastTransferredBytes * 1000) / elapsed.inMilliseconds;
  }

  /// Reset the speed calculator (useful when transfer restarts)
  void reset() {
    _speedSamples.clear();
    _lastSpeedUpdate = null;
    _lastTransferredBytes = 0;
    _smoothedSpeed = 0.0;
    _transferStartTime = null;
    _isHighThroughputMode = false;
  }

  /// Check if we have enough data to show meaningful speed
  bool hasValidSpeed(DateTime transferStartTime) {
    final timeSinceStart = DateTime.now().difference(transferStartTime);
    return timeSinceStart.inMilliseconds >= _minTimeForSpeedMs && _speedSamples.isNotEmpty;
  }
  
  /// Initialize with first progress point for better accuracy
  void initializeWithProgress(int initialBytes, DateTime timestamp) {
    _transferStartTime = timestamp;
    _lastTransferredBytes = initialBytes;
    _lastSpeedUpdate = timestamp;
    _smoothedSpeed = 0.0;
  }
}

class SpeedSample {
  final DateTime timestamp;
  final double speed; // bytes per second - raw calculation
  final double smoothedSpeed; // bytes per second - smoothed value

  SpeedSample(this.timestamp, this.speed, this.smoothedSpeed);
}