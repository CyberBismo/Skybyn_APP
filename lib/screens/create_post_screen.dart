import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui';
import '../services/post_service.dart';
import '../services/auth_service.dart';
import '../models/post.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';

class CreatePostScreen extends StatefulWidget {
  final bool isEditing;
  final Post? postToEdit;

  const CreatePostScreen({
    super.key,
    this.isEditing = false,
    this.postToEdit,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PostService _postService = PostService();
  final AuthService _authService = AuthService();
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();

    // If editing, populate the text field with existing content
    if (widget.isEditing && widget.postToEdit != null) {
      _contentController.text = widget.postToEdit!.content;
    }

    // Auto-focus the text field when the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // Removed unused _pickImage method

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(TranslationKeys.fieldRequired),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      if (widget.isEditing && widget.postToEdit != null) {
        // Update existing post
        await _postService.updatePost(
          postId: widget.postToEdit!.id,
          userId: userId,
          content: content,
        );

        if (mounted) {
          Navigator.of(context).pop('updated');
        }
      } else {
        // Create new post
        final result = await _postService.createPost(
          userId: userId,
          content: content,
        );

        // Send WebSocket message to notify other clients
        final postId = result['postID'];
        // WebSocketService().sendNewPost(postId);

        if (mounted) {
          // Return the post ID from the API response
          Navigator.of(context).pop(postId);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${widget.isEditing ? 'update' : 'create'} post: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          iconTheme: const IconThemeData(color: Colors.white),
          title: TranslatedText(
            widget.isEditing ? TranslationKeys.editPost : TranslationKeys.createPost,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          actions: [
            if (MediaQuery.of(context).viewInsets.bottom > 0)
              Container(
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: IconButton(
                  onPressed: _isPosting ? null : _submitPost,
                  icon: _isPosting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Icon(Icons.send, color: Colors.white, size: 24),
                  tooltip: 'Post',
                ),
              ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 40, // Account for status bar + app bar space
              left: 10,
              right: 10,
              bottom: 0,
            ),
            child: Stack(
              children: [
                // Main content
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20), // Space for app bar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child:                         ListenableBuilder(
                          listenable: TranslationService(),
                          builder: (context, _) {
                            return TextField(
                              controller: _contentController,
                              focusNode: _focusNode,
                              autofocus: true,
                              maxLines: 5,
                              minLines: 3,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: TranslationService().translate(TranslationKeys.whatOnMind),
                                hintStyle: const TextStyle(color: Colors.white70),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                              onTap: () {
                                // Ensure any other context menus are closed
                                // This helps prevent SystemContextMenu conflicts
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_selectedImage != null)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Image.file(
                                  _selectedImage!,
                                  height: 180,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Return placeholder on error
                                    return Container(
                                      height: 180,
                                      color: Colors.grey.withOpacity(0.3),
                                      child: const Center(
                                        child: Icon(Icons.error, color: Colors.grey),
                                      ),
                                    );
                                  },
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                      onPressed: () => setState(() => _selectedImage = null),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.3, // Add some space to push buttons down
                      ),
                      // Cancel button (only when keyboard is hidden)
                      if (MediaQuery.of(context).viewInsets.bottom == 0)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 80,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: _isPosting ? null : () => Navigator.of(context).pop(),
                                child: const TranslatedText(
                                  TranslationKeys.cancel,
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: IconButton(
                                  onPressed: _isPosting ? null : _submitPost,
                                  icon: _isPosting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Icon(Icons.send, color: Colors.white, size: 24),
                                  tooltip: 'Post',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
