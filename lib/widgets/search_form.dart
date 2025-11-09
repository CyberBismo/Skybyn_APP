import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'app_colors.dart';
import '../utils/translation_keys.dart';
import '../services/translation_service.dart';
import '../services/auth_service.dart';
import '../screens/profile_screen.dart';
import '../widgets/translated_text.dart';

/// Centralized styling for the SearchForm widget
class SearchFormStyles {
  // Sizes
  static const double borderRadius = 40.0; // Match web platform
  static const double iconSize = 24.0;
  static const double fontSize = 16.0;
  
  // Padding and margins - Updated to account for app bar positioning
  static const EdgeInsets formPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 10); // Reduced top padding
  static const EdgeInsets fieldPadding = EdgeInsets.symmetric(horizontal: 15, vertical: 10);
  static const EdgeInsets closeButtonPadding = EdgeInsets.only(right: 8.0);
  
  // Border radius
  static const double formRadius = 40.0; // Match web platform
  static const double fieldRadius = 40.0; // Match web platform
  
  // Shadows and effects
  static const double blurSigma = 5.0; // Match web platform blur
  static const double elevation = 0.0;
  
  // Animation
  static const Duration slideDuration = Duration(milliseconds: 200); // Match web
  static const Curve slideCurve = Curves.easeInOut;
}

class SearchForm extends StatefulWidget {
  final VoidCallback onClose;
  final Function(String) onSearch;
  final List<Map<String, dynamic>>? searchResults;
  final bool isSearching;

  const SearchForm({
    super.key,
    required this.onClose,
    required this.onSearch,
    this.searchResults,
    this.isSearching = false,
  });

  @override
  SearchFormState createState() => SearchFormState();
}

class SearchFormState extends State<SearchForm> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = Tween<Offset>(
      begin: const Offset(0.0, -1.0), // Start from top, outside screen
      end: Offset.zero, // End at top of screen
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
    
    // Auto-focus the search field when it appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });

    // Listen to text changes for real-time search
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    // Debounce search to avoid too many API calls
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      final query = _searchController.text.trim();
      if (query.isNotEmpty) {
        widget.onSearch(query);
      } else {
        // Clear results if search is empty
        widget.onSearch('');
      }
    });
  }

  // Public method to trigger the close animation
  void closeForm({bool runCallback = true}) {
    // Unfocus to prevent context menu conflicts
    _searchFocusNode.unfocus();
    _controller.reverse().then((_) {
      if (runCallback) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.dispose();
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formColor = AppColors.getFormColor(context);
    final textColor = AppColors.getTextColor(context);
    final hintColor = AppColors.getHintColor(context);

    return SlideTransition(
      position: _animation,
      child: Material(
        color: Colors.transparent,
        child: Container(
          // Position the search form within the app bar area
          margin: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20, // Reduced from 75 to 20 to move it higher
            left: 20,
            right: 20,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: SearchFormStyles.blurSigma, sigmaY: SearchFormStyles.blurSigma),
              child: Container(
                color: formColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search input section
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: SearchFormStyles.blurSigma, sigmaY: SearchFormStyles.blurSigma),
                          child: Container(
                            color: formColor,
                            child: Stack(
                              children: [
                                // Search input
                                ListenableBuilder(
                                  listenable: TranslationService(),
                                  builder: (context, _) {
                                    return TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      decoration: InputDecoration(
                                        hintText: TranslationService().translate(TranslationKeys.search),
                                        hintStyle: TextStyle(color: hintColor),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.only(
                                          left: 40, // Space for icon
                                          right: 40, // Space for close button
                                          top: 10,
                                          bottom: 10,
                                        ),
                                      ),
                                      style: TextStyle(color: textColor, fontSize: SearchFormStyles.fontSize),
                                      onSubmitted: (query) {
                                        _searchFocusNode.unfocus();
                                        widget.onSearch(query);
                                      },
                                      onTap: () {
                                        // Ensure any other context menus are closed
                                      },
                                    );
                                  },
                                ),
                                // Search icon (absolute positioned)
                                Positioned(
                                  left: 10,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: Icon(
                                      Icons.search,
                                      color: textColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                // Close button (absolute positioned)
                                Positioned(
                                  right: 10,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: () {
                                        closeForm();
                                      },
                                      child: Icon(
                                        Icons.close,
                                        color: textColor,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Search results section (if there are results)
                    if (widget.searchResults != null && widget.searchResults!.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(
                          maxHeight: 400, // Maximum height for results
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: widget.searchResults!.length,
                          itemBuilder: (context, index) {
                            final user = widget.searchResults![index];
                            return _buildSearchResultCard(user);
                          },
                        ),
                      )
                      else if (widget.isSearching)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> user) {
    final username = user['username']?.toString() ?? '';
    final nickname = user['nickname']?.toString() ?? username;
    final avatar = user['avatar']?.toString() ?? '';
    final online = user['online'] == 1 || user['online'] == '1' || user['online']?.toString() == '1';
    final friendStatus = user['friends']?.toString() ?? '0';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final authService = AuthService();
          final currentUserId = await authService.getStoredUserId();
          if (currentUserId != null && user['id']?.toString() == currentUserId) {
            return; // Don't navigate to own profile
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileScreen(userId: user['id']?.toString() ?? ''),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 50, // Fixed height to match avatar
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              // Avatar
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: CachedNetworkImage(
                      imageUrl: avatar,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey.withOpacity(0.3),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey.withOpacity(0.3),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                    ),
                  ),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Username/nickname column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (username != nickname)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                            height: 1.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
              // Friend status icon
              _buildFriendStatusIcon(friendStatus),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendStatusIcon(String friendStatus) {
    switch (friendStatus) {
      case '1': // Friends
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 20,
        );
      case '2': // Received request
        return const Icon(
          Icons.person_add_alt_1,
          color: Colors.orange,
          size: 20,
        );
      case '3': // Sent request
        return const Icon(
          Icons.hourglass_empty,
          color: Colors.blue,
          size: 20,
        );
      default: // Not friends
        return Icon(
          Icons.person_add,
          color: Colors.white.withOpacity(0.5),
          size: 20,
        );
    }
  }
}