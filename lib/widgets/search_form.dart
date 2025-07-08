import 'package:flutter/material.dart';
import 'dart:ui';

/// Centralized styling for the SearchForm widget
class SearchFormStyles {
  // Colors
  static const Color lightFormColor = Color(0x33FFFFFF); // White with 20% opacity
  static const Color darkFormColor = Color(0x4D000000); // Black with 30% opacity
  static const Color lightFieldColor = Color(0x1AFFFFFF); // White with 10% opacity
  static const Color darkFieldColor = Color(0x1A000000); // Black with 10% opacity
  static const Color lightTextColor = Colors.black;
  static const Color darkTextColor = Colors.white;
  static const Color lightHintColor = Color(0xB3FFFFFF); // White with 70% opacity
  static const Color darkHintColor = Color(0x99000000); // Black with 60% opacity
  
  // Sizes
  static const double borderRadius = 30.0;
  static const double iconSize = 24.0;
  static const double fontSize = 16.0;
  
  // Padding and margins
  static const EdgeInsets formPadding = EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 16);
  static const EdgeInsets fieldPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  static const EdgeInsets closeButtonPadding = EdgeInsets.only(right: 8.0);
  
  // Border radius
  static const double formRadius = 30.0;
  static const double fieldRadius = 25.0;
  
  // Shadows and effects
  static const double blurSigma = 10.0;
  static const double elevation = 0.0;
  
  // Animation
  static const Duration slideDuration = Duration(milliseconds: 300);
  static const Curve slideCurve = Curves.easeInOut;
  
  // Theme-aware color getters
  static Color getFormColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkFormColor : lightFormColor;
  }
  
  static Color getFieldColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkFieldColor : lightFieldColor;
  }
  
  static Color getTextColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkTextColor : lightTextColor;
  }
  
  static Color getHintColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? darkHintColor : lightHintColor;
  }
}

class SearchForm extends StatefulWidget {
  final VoidCallback onClose;
  final Function(String) onSearch;

  const SearchForm({
    Key? key,
    required this.onClose,
    required this.onSearch,
  }) : super(key: key);

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
    final formColor = SearchFormStyles.getFormColor(context);
    final fieldColor = SearchFormStyles.getFieldColor(context);
    final textColor = SearchFormStyles.getTextColor(context);
    final hintColor = SearchFormStyles.getHintColor(context);

    return SlideTransition(
      position: _animation,
      child: Material(
        color: Colors.transparent, // Ensure Material doesn't block blur
        child: Container(
          padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 16),
          child: SafeArea(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SearchFormStyles.fieldRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: SearchFormStyles.blurSigma, sigmaY: SearchFormStyles.blurSigma),
                child: Container(
                  padding: SearchFormStyles.fieldPadding,
                  color: fieldColor,
                  child: Row(
                    children: [
                      Icon(Icons.search, color: textColor, size: SearchFormStyles.iconSize),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search Skybyn...',
                            hintStyle: TextStyle(color: hintColor),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(color: textColor, fontSize: SearchFormStyles.fontSize),
                          onSubmitted: (query) {
                            _searchFocusNode.unfocus();
                            widget.onSearch(query);
                          },
                          onTap: () {
                            // Ensure any other context menus are closed
                            // This helps prevent SystemContextMenu conflicts
                          },
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          closeForm();
                        },
                        child: Icon(Icons.close, color: textColor, size: SearchFormStyles.iconSize),
                      ),
                    ],
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