import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../utils/translation_keys.dart';
import 'translated_text.dart';

class LanguageSelector extends StatefulWidget {
  final Function(String)? onLanguageChanged;
  final bool showTitle;
  final EdgeInsetsGeometry? padding;
  final TextStyle? titleStyle;
  final TextStyle? itemStyle;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? unselectedColor;
  final double? elevation;
  final ShapeBorder? shape;

  const LanguageSelector({
    Key? key,
    this.onLanguageChanged,
    this.showTitle = true,
    this.padding,
    this.titleStyle,
    this.itemStyle,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
    this.elevation,
    this.shape,
  }) : super(key: key);

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  late String _selectedLanguage;
  final TranslationService _translationService = TranslationService();

  @override
  void initState() {
    super.initState();
    _selectedLanguage = _translationService.currentLanguage;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: widget.elevation ?? 2,
      shape: widget.shape,
      color: widget.backgroundColor ?? theme.cardColor,
      child: Padding(
        padding: widget.padding ?? const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showTitle) ...[
              Row(
                children: [
                  Icon(
                    Icons.language,
                    color: theme.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  TranslatedText(
                    TranslationKeys.selectLanguage,
                    style: widget.titleStyle ?? 
                           theme.textTheme.titleMedium?.copyWith(
                             fontWeight: FontWeight.bold,
                           ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            ...TranslationService.supportedLanguages.map((languageCode) {
              final isSelected = _selectedLanguage == languageCode;
              final languageName = _translationService.getLanguageName(languageCode);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: Icon(
                    Icons.language,
                    color: isSelected 
                        ? (widget.selectedColor ?? theme.primaryColor)
                        : (widget.unselectedColor ?? theme.iconTheme.color),
                    size: 20,
                  ),
                  title: Text(
                    languageName,
                    style: widget.itemStyle ?? 
                           theme.textTheme.bodyLarge?.copyWith(
                             color: isSelected 
                                 ? (widget.selectedColor ?? theme.primaryColor)
                                 : (widget.unselectedColor ?? theme.textTheme.bodyLarge?.color),
                             fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                           ),
                  ),
                  trailing: isSelected 
                      ? Icon(
                          Icons.check_circle,
                          color: widget.selectedColor ?? theme.primaryColor,
                          size: 20,
                        )
                      : null,
                  selected: isSelected,
                  selectedTileColor: (widget.selectedColor ?? theme.primaryColor).withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () => _selectLanguage(languageCode),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _selectLanguage(String languageCode) async {
    if (languageCode != _selectedLanguage) {
      setState(() {
        _selectedLanguage = languageCode;
      });

      // Update language in service
      await _translationService.setLanguage(languageCode);

      // Notify parent widget
      if (widget.onLanguageChanged != null) {
        widget.onLanguageChanged!(languageCode);
      }

      // Show confirmation snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(
              TranslationKeys.languageChanged,
              fallback: 'Language changed successfully!',
            ),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: TranslationKeys.ok,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }
}

// Compact language selector for app bars or smaller spaces
class CompactLanguageSelector extends StatelessWidget {
  final Function(String)? onLanguageChanged;
  final String? currentLanguage;
  final Color? iconColor;
  final double? iconSize;

  const CompactLanguageSelector({
    Key? key,
    this.onLanguageChanged,
    this.currentLanguage,
    this.iconColor,
    this.iconSize = 24,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final translationService = TranslationService();
    final currentLang = currentLanguage ?? translationService.currentLanguage;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.language,
        color: iconColor ?? Theme.of(context).iconTheme.color,
        size: iconSize,
      ),
      tooltip: TranslationKeys.selectLanguage,
      onSelected: (String languageCode) async {
        if (languageCode != currentLang) {
          await translationService.setLanguage(languageCode);
          if (onLanguageChanged != null) {
            onLanguageChanged!(languageCode);
          }
        }
      },
      itemBuilder: (BuildContext context) {
        return TranslationService.supportedLanguages.map((String languageCode) {
          final isSelected = languageCode == currentLang;
          final name = translationService.getLanguageName(languageCode);
          
          return PopupMenuItem<String>(
            value: languageCode,
            child: Row(
              children: [
                Icon(
                  Icons.language,
                  color: isSelected 
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).iconTheme.color,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isSelected 
                          ? Theme.of(context).primaryColor
                          : Theme.of(context).textTheme.bodyLarge?.color,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    color: Theme.of(context).primaryColor,
                    size: 16,
                  ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}

// Language selector dialog
class LanguageSelectorDialog extends StatefulWidget {
  final String? currentLanguage;
  final Function(String)? onLanguageChanged;

  const LanguageSelectorDialog({
    Key? key,
    this.currentLanguage,
    this.onLanguageChanged,
  }) : super(key: key);

  @override
  State<LanguageSelectorDialog> createState() => _LanguageSelectorDialogState();
}

class _LanguageSelectorDialogState extends State<LanguageSelectorDialog> {
  late String _selectedLanguage;
  final TranslationService _translationService = TranslationService();

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.currentLanguage ?? _translationService.currentLanguage;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.language,
            color: theme.primaryColor,
            size: 24,
          ),
          const SizedBox(width: 8),
          TranslatedText(TranslationKeys.selectLanguage),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: TranslationService.supportedLanguages.length,
          itemBuilder: (context, index) {
            final languageCode = TranslationService.supportedLanguages[index];
            final isSelected = _selectedLanguage == languageCode;
            final languageName = _translationService.getLanguageName(languageCode);
            
            return ListTile(
              leading: Icon(
                Icons.language,
                color: isSelected 
                    ? theme.primaryColor
                    : theme.iconTheme.color,
                size: 20,
              ),
              title: Text(
                languageName,
                style: TextStyle(
                  color: isSelected 
                      ? theme.primaryColor
                      : theme.textTheme.bodyLarge?.color,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected 
                  ? Icon(
                      Icons.check_circle,
                      color: theme.primaryColor,
                      size: 20,
                    )
                  : null,
              selected: isSelected,
              selectedTileColor: theme.primaryColor.withOpacity(0.1),
              onTap: () {
                setState(() {
                  _selectedLanguage = languageCode;
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: TranslatedText(TranslationKeys.cancel),
        ),
        ElevatedButton(
          onPressed: _selectedLanguage != (widget.currentLanguage ?? _translationService.currentLanguage)
              ? () => _applyLanguage()
              : null,
          child: TranslatedText(TranslationKeys.apply),
        ),
      ],
    );
  }

  void _applyLanguage() async {
    await _translationService.setLanguage(_selectedLanguage);
    if (widget.onLanguageChanged != null) {
      widget.onLanguageChanged!(_selectedLanguage);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
