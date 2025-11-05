import 'package:flutter/material.dart';
import 'dart:ui';
import 'app_colors.dart';
import '../utils/translation_keys.dart';
import '../services/translation_service.dart';

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

  const SearchForm({
    super.key,
    required this.onClose,
    required this.onSearch,
  });

  @override
  SearchFormState createState() => SearchFormState();
}

class SearchFormState extends State<SearchForm> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

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
                child: Padding(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
} 