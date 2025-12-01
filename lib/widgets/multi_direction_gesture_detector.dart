import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Swipe direction enum
enum SwipeDirection {
  left,
  right,
  up,
  down,
  none,
}

/// Callback for when a swipe is detected
typedef SwipeCallback = void Function(SwipeDirection direction, double progress);

/// Multi-directional gesture detector similar to Snapchat's navigation
/// Handles horizontal and vertical swipes with progress tracking
class MultiDirectionGestureDetector extends StatefulWidget {
  final Widget child;
  final SwipeCallback? onSwipeStart;
  final SwipeCallback? onSwipeUpdate;
  final SwipeCallback? onSwipeEnd;
  final double swipeThreshold; // Minimum distance to trigger swipe (default: 0.3 = 30% of screen)
  final double velocityThreshold; // Minimum velocity for fast swipe (default: 500 pixels/second)
  final bool enableHorizontal;
  final bool enableVertical;

  const MultiDirectionGestureDetector({
    super.key,
    required this.child,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.swipeThreshold = 0.3,
    this.velocityThreshold = 500.0,
    this.enableHorizontal = true,
    this.enableVertical = true,
  });

  @override
  State<MultiDirectionGestureDetector> createState() => _MultiDirectionGestureDetectorState();
}

class _MultiDirectionGestureDetectorState extends State<MultiDirectionGestureDetector> {
  Offset _dragStart = Offset.zero;
  Offset _dragCurrent = Offset.zero;
  DateTime _dragStartTime = DateTime.now();
  DateTime _lastMoveTime = DateTime.now();
  Offset _lastMovePosition = Offset.zero;
  bool _isDragging = false;
  bool _isHorizontalGesture = false;
  SwipeDirection _currentDirection = SwipeDirection.none;
  double _horizontalProgress = 0.0;
  double _verticalProgress = 0.0;

  void _handlePanStart(DragStartDetails details) {
    _dragStart = details.globalPosition;
    _dragCurrent = _dragStart;
    _isDragging = true;
    _isHorizontalGesture = false;
    _currentDirection = SwipeDirection.none;
    _horizontalProgress = 0.0;
    _verticalProgress = 0.0;
    widget.onSwipeStart?.call(SwipeDirection.none, 0.0);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    _dragCurrent = details.globalPosition;
    final delta = _dragCurrent - _dragStart;
    final screenSize = MediaQuery.of(context).size;

    // Calculate progress for both directions
    final horizontalDelta = delta.dx;
    final verticalDelta = delta.dy;
    final absHorizontalDelta = horizontalDelta.abs();
    final absVerticalDelta = verticalDelta.abs();
    
    // Determine if this is primarily a horizontal or vertical gesture
    // Once we determine it's horizontal, mark it so we can block vertical scrolling
    if (!_isHorizontalGesture && absHorizontalDelta > 10 && absHorizontalDelta > absVerticalDelta * 1.5) {
      _isHorizontalGesture = true;
    }
    
    _horizontalProgress = widget.enableHorizontal 
        ? (horizontalDelta / screenSize.width).clamp(-1.0, 1.0)
        : 0.0;
    _verticalProgress = widget.enableVertical
        ? (verticalDelta / screenSize.height).clamp(-1.0, 1.0)
        : 0.0;

    // Determine primary direction based on which has more movement
    final absHorizontal = _horizontalProgress.abs();
    final absVertical = _verticalProgress.abs();

    SwipeDirection newDirection = SwipeDirection.none;
    double progress = 0.0;

    if (absHorizontal > absVertical && absHorizontal > 0.05) {
      // Horizontal swipe is dominant
      if (horizontalDelta > 0) {
        newDirection = SwipeDirection.right;
        progress = _horizontalProgress;
      } else {
        newDirection = SwipeDirection.left;
        progress = _horizontalProgress.abs();
      }
    } else if (absVertical > absHorizontal && absVertical > 0.05) {
      // Vertical swipe is dominant
      if (verticalDelta > 0) {
        newDirection = SwipeDirection.down;
        progress = _verticalProgress;
      } else {
        newDirection = SwipeDirection.up;
        progress = _verticalProgress.abs();
      }
    }

    // Update direction if it changed
    if (newDirection != _currentDirection) {
      _currentDirection = newDirection;
    }

    // Call update callback
    if (_currentDirection != SwipeDirection.none) {
      widget.onSwipeUpdate?.call(_currentDirection, progress);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_isDragging) return;

    final screenSize = MediaQuery.of(context).size;
    final delta = _dragCurrent - _dragStart;
    final velocity = details.velocity;

    // Calculate final progress
    final horizontalDelta = delta.dx;
    final verticalDelta = delta.dy;
    final horizontalProgress = widget.enableHorizontal
        ? (horizontalDelta / screenSize.width).clamp(-1.0, 1.0)
        : 0.0;
    final verticalProgress = widget.enableVertical
        ? (verticalDelta / screenSize.height).clamp(-1.0, 1.0)
        : 0.0;

    // Determine which direction won
    final absHorizontal = horizontalProgress.abs();
    final absVertical = verticalProgress.abs();

    SwipeDirection finalDirection = SwipeDirection.none;
    double finalProgress = 0.0;
    double finalVelocity = 0.0;

    if (absHorizontal > absVertical && absHorizontal > 0.05) {
      // Horizontal swipe won
      if (horizontalDelta > 0) {
        finalDirection = SwipeDirection.right;
        finalProgress = horizontalProgress;
        finalVelocity = velocity.pixelsPerSecond.dx;
      } else {
        finalDirection = SwipeDirection.left;
        finalProgress = absHorizontal;
        finalVelocity = velocity.pixelsPerSecond.dx.abs();
      }
    } else if (absVertical > absHorizontal && absVertical > 0.05) {
      // Vertical swipe won
      if (verticalDelta > 0) {
        finalDirection = SwipeDirection.down;
        finalProgress = verticalProgress;
        finalVelocity = velocity.pixelsPerSecond.dy;
      } else {
        finalDirection = SwipeDirection.up;
        finalProgress = absVertical;
        finalVelocity = velocity.pixelsPerSecond.dy.abs();
      }
    }

    // Check if swipe threshold is met
    final meetsThreshold = finalProgress >= widget.swipeThreshold ||
        (finalProgress >= 0.1 && finalVelocity >= widget.velocityThreshold);

    if (meetsThreshold && finalDirection != SwipeDirection.none) {
      widget.onSwipeEnd?.call(finalDirection, finalProgress);
    }

    // Reset state
    _isDragging = false;
    _isHorizontalGesture = false;
    _currentDirection = SwipeDirection.none;
    _horizontalProgress = 0.0;
    _verticalProgress = 0.0;
  }

  void _handlePanCancel() {
    _isDragging = false;
    _isHorizontalGesture = false;
    _currentDirection = SwipeDirection.none;
    _horizontalProgress = 0.0;
    _verticalProgress = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // Start tracking but don't block yet
        _dragStart = event.position;
        _dragCurrent = _dragStart;
        _dragStartTime = DateTime.now();
        _lastMoveTime = DateTime.now();
        _lastMovePosition = event.position;
        _isDragging = true;
        _isHorizontalGesture = false;
        _currentDirection = SwipeDirection.none;
        _horizontalProgress = 0.0;
        _verticalProgress = 0.0;
        widget.onSwipeStart?.call(SwipeDirection.none, 0.0);
      },
      onPointerMove: (PointerMoveEvent event) {
        if (!_isDragging) return;
        
        _dragCurrent = event.position;
        final now = DateTime.now();
        _lastMoveTime = now;
        _lastMovePosition = event.position;
        
        final delta = _dragCurrent - _dragStart;
        final absHorizontalDelta = delta.dx.abs();
        final absVerticalDelta = delta.dy.abs();
        
        // Determine if this is primarily horizontal (threshold: 1.5x more horizontal than vertical)
        if (!_isHorizontalGesture && absHorizontalDelta > 10 && absHorizontalDelta > absVerticalDelta * 1.5) {
          _isHorizontalGesture = true;
        }
        
        // Only process if it's a horizontal gesture
        if (_isHorizontalGesture) {
          final screenSize = MediaQuery.of(context).size;
          final horizontalDelta = delta.dx;
          final verticalDelta = delta.dy;
          
          _horizontalProgress = widget.enableHorizontal 
              ? (horizontalDelta / screenSize.width).clamp(-1.0, 1.0)
              : 0.0;
          _verticalProgress = widget.enableVertical
              ? (verticalDelta / screenSize.height).clamp(-1.0, 1.0)
              : 0.0;

          final absHorizontal = _horizontalProgress.abs();
          final absVertical = _verticalProgress.abs();

          SwipeDirection newDirection = SwipeDirection.none;
          double progress = 0.0;

          if (absHorizontal > absVertical && absHorizontal > 0.05) {
            if (horizontalDelta > 0) {
              newDirection = SwipeDirection.right;
              progress = _horizontalProgress;
            } else {
              newDirection = SwipeDirection.left;
              progress = _horizontalProgress.abs();
            }
          } else if (absHorizontal > 0.01) {
            // Even if not dominant, if there's horizontal movement, determine direction for smooth feedback
            if (horizontalDelta > 0) {
              newDirection = SwipeDirection.right;
              progress = _horizontalProgress;
            } else {
              newDirection = SwipeDirection.left;
              progress = _horizontalProgress.abs();
            }
          }

          if (newDirection != _currentDirection) {
            _currentDirection = newDirection;
          }

          // Always call onSwipeUpdate for smooth visual feedback when there's horizontal movement
          if (absHorizontal > 0.01 && widget.enableHorizontal) {
            widget.onSwipeUpdate?.call(_currentDirection != SwipeDirection.none ? _currentDirection : (horizontalDelta > 0 ? SwipeDirection.right : SwipeDirection.left), progress);
          }
        }
      },
      onPointerUp: (PointerUpEvent event) {
        if (!_isDragging) return;
        
        if (_isHorizontalGesture) {
          final screenSize = MediaQuery.of(context).size;
          final delta = _dragCurrent - _dragStart;
          final horizontalDelta = delta.dx;
          final horizontalProgress = widget.enableHorizontal
              ? (horizontalDelta / screenSize.width).clamp(-1.0, 1.0)
              : 0.0;
          final absHorizontal = horizontalProgress.abs();

          // Calculate velocity manually
          final duration = DateTime.now().difference(_dragStartTime);
          final durationSeconds = duration.inMilliseconds / 1000.0;
          double finalVelocity = 0.0;
          if (durationSeconds > 0) {
            finalVelocity = (horizontalDelta / durationSeconds).abs();
          }

          SwipeDirection finalDirection = SwipeDirection.none;
          double finalProgress = 0.0;

          if (absHorizontal > 0.05) {
            if (horizontalDelta > 0) {
              finalDirection = SwipeDirection.right;
              finalProgress = horizontalProgress;
            } else {
              finalDirection = SwipeDirection.left;
              finalProgress = absHorizontal;
            }
          }

          final meetsThreshold = finalProgress >= widget.swipeThreshold ||
              (finalProgress >= 0.1 && finalVelocity >= widget.velocityThreshold);

          // Always call onSwipeEnd to allow snap-back even if threshold isn't met
          if (finalDirection != SwipeDirection.none) {
            widget.onSwipeEnd?.call(finalDirection, finalProgress);
          } else if (_isHorizontalGesture) {
            // If we had a horizontal gesture but no clear direction, still call with none
            widget.onSwipeEnd?.call(SwipeDirection.none, 0.0);
          }
        } else {
          // If not a horizontal gesture, still notify to allow cleanup
          widget.onSwipeEnd?.call(SwipeDirection.none, 0.0);
        }

        _isDragging = false;
        _isHorizontalGesture = false;
        _currentDirection = SwipeDirection.none;
        _horizontalProgress = 0.0;
        _verticalProgress = 0.0;
      },
      onPointerCancel: (PointerCancelEvent event) {
        _isDragging = false;
        _isHorizontalGesture = false;
        _currentDirection = SwipeDirection.none;
        _horizontalProgress = 0.0;
        _verticalProgress = 0.0;
      },
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

