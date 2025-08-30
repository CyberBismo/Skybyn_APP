import 'package:flutter/material.dart';
import 'dart:ui';

class ChatListModal extends StatelessWidget {
  const ChatListModal({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> chats = [
      {
        'avatar': 'https://randomuser.me/api/portraits/men/1.jpg',
        'username': 'Raymond303',
        'lastMessage': 'Hey, how are you?',
      },
      {
        'avatar': 'https://randomuser.me/api/portraits/women/2.jpg',
        'username': 'YenZenAI',
        'lastMessage': 'Let\'s meet tomorrow!',
      },
      {
        'avatar': 'https://randomuser.me/api/portraits/men/3.jpg',
        'username': 'CyberByte',
        'lastMessage': 'See you soon!',
      },
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.white.withOpacity(0.05),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Colors.white.withOpacity(0.12),
                      child: const TextField(
                        decoration: InputDecoration(
                          hintText: 'Search chats...',
                          hintStyle: TextStyle(color: Colors.white70),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search, color: Colors.white),
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              // Chat list
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: chats.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: NetworkImage(chat['avatar']!),
                            radius: 22,
                          ),
                          title: Text(
                            chat['username']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            chat['lastMessage']!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            // TODO: Open chat
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
} 