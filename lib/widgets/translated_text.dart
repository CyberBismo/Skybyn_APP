import 'package:flutter/material.dart';
import '../services/translation_service.dart';

class TranslatedText extends StatelessWidget {
  final String textKey;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? fallback;

  const TranslatedText(
    this.textKey, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final translationService = TranslationService();
    
    // Listen to translation service changes
    return ListenableBuilder(
      listenable: translationService,
      builder: (context, child) {
        final translatedText = translationService.translate(textKey);
        
        // If translation is the same as key and fallback is provided, use fallback
        final displayText = (translatedText == textKey && fallback != null) 
            ? fallback! 
            : translatedText;

        return Text(
          displayText,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap ?? true,
        );
      },
    );
  }
}

// Extension for easy translation on String
// Note: This extension does NOT listen to language changes.
// For reactive translations that update when language changes,
// use TranslatedText widget instead.
extension StringTranslation on String {
  String get tr {
    return TranslationService().translate(this);
  }
}

// Reactive Text widget that updates when language changes
// Use this instead of Text(key.tr) when you need automatic updates
class ReactiveTranslatedText extends StatelessWidget {
  final String translationKey;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? fallback;

  const ReactiveTranslatedText(
    this.translationKey, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final translationService = TranslationService();
    
    return ListenableBuilder(
      listenable: translationService,
      builder: (context, child) {
        final translatedText = translationService.translate(translationKey);
        final displayText = (translatedText == translationKey && fallback != null) 
            ? fallback! 
            : translatedText;
        
        return Text(
          displayText,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap ?? true,
        );
      },
    );
  }
}

// Helper class for common translated widgets
class TranslatedWidgets {
  static Widget text(
    String key, {
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
    String? fallback,
  }) {
    return TranslatedText(
      key,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      fallback: fallback,
    );
  }

  static Widget button(
    String key, {
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    Clip clipBehavior = Clip.none,
    String? fallback,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      clipBehavior: clipBehavior,
      child: TranslatedText(key, fallback: fallback),
    );
  }

  static Widget textButton(
    String key, {
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    Clip clipBehavior = Clip.none,
    String? fallback,
  }) {
    return TextButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      clipBehavior: clipBehavior,
      child: TranslatedText(key, fallback: fallback),
    );
  }

  static Widget outlinedButton(
    String key, {
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    Clip clipBehavior = Clip.none,
    String? fallback,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      clipBehavior: clipBehavior,
      child: TranslatedText(key, fallback: fallback),
    );
  }

  static Widget appBar(
    String key, {
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
    Widget? title,
    PreferredSizeWidget? bottom,
    double? elevation,
    Color? shadowColor,
    ShapeBorder? shape,
    Color? backgroundColor,
    Color? foregroundColor,
    IconThemeData? iconTheme,
    IconThemeData? actionsIconTheme,
    bool primary = true,
    bool centerTitle = true,
    double? titleSpacing,
    double? toolbarHeight,
    String? fallback,
  }) {
    return AppBar(
      title: title ?? TranslatedText(key, fallback: fallback),
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      bottom: bottom,
      elevation: elevation,
      shadowColor: shadowColor,
      shape: shape,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      iconTheme: iconTheme,
      actionsIconTheme: actionsIconTheme,
      primary: primary,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      toolbarHeight: toolbarHeight,
    );
  }

  static Widget listTile(
    String key, {
    Widget? leading,
    Widget? title,
    Widget? subtitle,
    Widget? trailing,
    bool isThreeLine = false,
    bool? dense,
    VisualDensity? visualDensity,
    ShapeBorder? shape,
    EdgeInsetsGeometry? contentPadding,
    bool enabled = true,
    GestureTapCallback? onTap,
    GestureLongPressCallback? onLongPress,
    MouseCursor? mouseCursor,
    bool selected = false,
    Color? focusColor,
    Color? hoverColor,
    Color? tileColor,
    Color? selectedTileColor,
    String? fallback,
  }) {
    return ListTile(
      leading: leading,
      title: title ?? TranslatedText(key, fallback: fallback),
      subtitle: subtitle,
      trailing: trailing,
      isThreeLine: isThreeLine,
      dense: dense,
      visualDensity: visualDensity,
      shape: shape,
      contentPadding: contentPadding,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      mouseCursor: mouseCursor,
      selected: selected,
      focusColor: focusColor,
      hoverColor: hoverColor,
      tileColor: tileColor,
      selectedTileColor: selectedTileColor,
    );
  }

  static Widget dialog(
    String key, {
    Widget? title,
    Widget? content,
    List<Widget>? actions,
    String? fallback,
  }) {
    return AlertDialog(
      title: title ?? TranslatedText(key, fallback: fallback),
      content: content,
      actions: actions,
    );
  }
}
