import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Custom cache manager for all network images in the app.
/// - 30-day stale period (avatars rarely change)
/// - 500 max cached objects before LRU eviction
/// - Shared instance used across all widgets
class SkybynCacheManager extends CacheManager {
  static const String key = 'skybynImageCache';

  static final SkybynCacheManager _instance = SkybynCacheManager._();
  factory SkybynCacheManager() => _instance;

  SkybynCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 500,
        ));
}
