import 'dart:collection';

/// Adaptive tuner that adjusts DPFTP parameters based on network conditions
class AdaptiveTuner {
  // RTT tracking
  final Queue<int> _rttSamples = Queue();
  static const int _maxSamples = 20;

  // Timing
  final Map<int, DateTime> _chunkSentTimes = {};

  // Current settings
  int _currentChunkSize = 4 * 1024 * 1024; // Start with 4 MB
  int _currentWindowSize = 256 * 1024 * 1024; // Start with 256 MB

  // Tuning parameters
  static const int _minChunkSize = 2 * 1024 * 1024; // 2 MB
  static const int _maxChunkSize = 8 * 1024 * 1024; // 8 MB
  static const int _minWindowSize = 128 * 1024 * 1024; // 128 MB
  static const int _maxWindowSize = 512 * 1024 * 1024; // 512 MB

  // Adjustment thresholds (in milliseconds)
  static const int _lowLatencyThreshold = 50;
  static const int _mediumLatencyThreshold = 100;
  static const int _highLatencyThreshold = 200;

  // Hysteresis to prevent oscillation
  int _adjustmentCounter = 0;
  static const int _adjustmentInterval = 10; // Adjust every 10 chunks

  /// Record when a chunk was sent
  void recordChunkSent(int chunkId) {
    _chunkSentTimes[chunkId] = DateTime.now();
  }

  /// Record when ACK was received and calculate RTT
  void recordChunkAck(int chunkId) {
    if (!_chunkSentTimes.containsKey(chunkId)) return;

    final sentTime = _chunkSentTimes.remove(chunkId)!;
    final rtt = DateTime.now().difference(sentTime).inMilliseconds;

    // Add to samples
    _rttSamples.add(rtt);
    if (_rttSamples.length > _maxSamples) {
      _rttSamples.removeFirst();
    }

    // Adjust parameters periodically
    _adjustmentCounter++;
    if (_adjustmentCounter >= _adjustmentInterval) {
      _adjustmentCounter = 0;
      _adjustParameters();
    }
  }

  /// Get current recommended chunk size
  int get chunkSize => _currentChunkSize;

  /// Get current recommended window size
  int get windowSize => _currentWindowSize;

  /// Get average RTT
  int get averageRTT {
    if (_rttSamples.isEmpty) return 0;
    return _rttSamples.reduce((a, b) => a + b) ~/ _rttSamples.length;
  }

  /// Get RTT percentile (for detecting spikes)
  int getRTTPercentile(double percentile) {
    if (_rttSamples.isEmpty) return 0;
    final sorted = _rttSamples.toList()..sort();
    final index = (sorted.length * percentile).floor();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  /// Adjust parameters based on network conditions
  void _adjustParameters() {
    if (_rttSamples.length < 5) return; // Need enough samples

    final avgRTT = averageRTT;
    final p95RTT = getRTTPercentile(0.95); // 95th percentile

    // Adjust chunk size based on average RTT
    final newChunkSize = _calculateOptimalChunkSize(avgRTT);

    // Adjust window size based on bandwidth-delay product
    // Window = Bandwidth × RTT × Safety Factor
    // Assume 300 Mbps = 37.5 MB/s, safety factor = 2
    final bdp = (37.5 * (p95RTT / 1000.0) * 2).toInt() * 1024 * 1024;
    final newWindowSize = bdp.clamp(_minWindowSize, _maxWindowSize);

    // Apply changes with hysteresis (only if significant change)
    if ((newChunkSize - _currentChunkSize).abs() >= 1024 * 1024) {
      _currentChunkSize = newChunkSize;
    }

    if ((newWindowSize - _currentWindowSize).abs() >= 32 * 1024 * 1024) {
      _currentWindowSize = newWindowSize;
    }
  }

  /// Calculate optimal chunk size based on RTT
  int _calculateOptimalChunkSize(int rtt) {
    if (rtt < _lowLatencyThreshold) {
      // Low latency: use large chunks (8 MB)
      return _maxChunkSize;
    } else if (rtt < _mediumLatencyThreshold) {
      // Medium latency: use 6 MB chunks
      return 6 * 1024 * 1024;
    } else if (rtt < _highLatencyThreshold) {
      // High latency: use 4 MB chunks
      return 4 * 1024 * 1024;
    } else {
      // Very high latency: use small chunks (2 MB)
      return _minChunkSize;
    }
  }

  /// Reset tuner state
  void reset() {
    _rttSamples.clear();
    _chunkSentTimes.clear();
    _adjustmentCounter = 0;
    _currentChunkSize = 4 * 1024 * 1024;
    _currentWindowSize = 256 * 1024 * 1024;
  }

  /// Get tuning statistics for debugging
  Map<String, dynamic> getStats() {
    return {
      'avgRTT': averageRTT,
      'p95RTT': getRTTPercentile(0.95),
      'chunkSize': _currentChunkSize ~/ (1024 * 1024),
      'windowSize': _currentWindowSize ~/ (1024 * 1024),
      'samples': _rttSamples.length,
    };
  }
}
