import 'dart:async';
import 'package:flutter/material.dart';

/// Throttles touch input to ~60fps (16ms intervals) to prevent ANR
/// Samsung devices have aggressive ANR watchdog, so we must keep UI thread responsive
class TouchThrottler {
  static const Duration _throttleInterval = Duration(milliseconds: 16); // ~60fps
  DateTime? _lastUpdateTime;
  Timer? _throttleTimer;
  Offset? _pendingUpdate;
  final Function(Offset) _onUpdate;

  TouchThrottler(this._onUpdate);

  /// Process touch update with throttling
  void update(Offset position) {
    final now = DateTime.now();
    
    // If enough time has passed since last update, process immediately
    if (_lastUpdateTime == null || 
        now.difference(_lastUpdateTime!) >= _throttleInterval) {
      _lastUpdateTime = now;
      _onUpdate(position);
      _pendingUpdate = null;
    } else {
      // Store pending update and schedule it
      _pendingUpdate = position;
      
      // Cancel existing timer
      _throttleTimer?.cancel();
      
      // Schedule update after throttle interval
      final delay = _throttleInterval - now.difference(_lastUpdateTime!);
      _throttleTimer = Timer(delay, () {
        if (_pendingUpdate != null) {
          _lastUpdateTime = DateTime.now();
          _onUpdate(_pendingUpdate!);
          _pendingUpdate = null;
        }
      });
    }
  }

  /// Flush any pending updates
  void flush() {
    _throttleTimer?.cancel();
    if (_pendingUpdate != null) {
      _onUpdate(_pendingUpdate!);
      _pendingUpdate = null;
    }
  }

  /// Dispose resources
  void dispose() {
    _throttleTimer?.cancel();
    _pendingUpdate = null;
  }
}

