# Skybyn Mobile App

A secure application with modern UI/UX and comprehensive authentication features.

## 🚀 Features

### Core Features
- **Secure Authentication** - User login/logout with credential storage
- **QR Code Scanner** - Camera-based QR code authentication
- **Real-time Updates** - WebSocket integration for live data
- **Modern UI** - Beautiful gradient backgrounds and smooth animations
- **Cross-platform** - iOS and Android support

### User Interface
- **Custom Splash Screen** - Branded loading experience with fade transitions
- **Responsive Design** - Adapts to different screen sizes
- **Dark/Light Theme** - Theme switching capability
- **Smooth Navigation** - Seamless screen transitions

### Technical Features
- **Local Authentication** - Biometric authentication support
- **Secure Storage** - Encrypted local data storage
- **HTTP Client** - RESTful API integration
- **Image Handling** - Advanced image processing and caching
- **Database** - SQLite local database
- **Notifications** - Local push notifications

## 📱 Screenshots

- **Splash Screen** - Custom branded loading screen
- **Login Screen** - Secure authentication interface
- **Home Screen** - Main application dashboard
- **Profile Screen** - User profile management
- **Settings Screen** - Application configuration
- **QR Scanner** - Camera-based authentication
- **Notification Test** - Notification system testing

## 🛠️ Technology Stack

- **Framework**: Flutter 3.32.5
- **Language**: Dart
- **State Management**: Provider
- **Database**: SQLite (sqflite)
- **HTTP Client**: http package
- **Image Processing**: extended_image, cached_network_image
- **Authentication**: local_auth, flutter_secure_storage
- **QR Scanning**: mobile_scanner
- **Real-time**: web_socket_channel
- **UI Components**: Custom widgets with Material Design

## 📋 Prerequisites

- Flutter SDK (3.32.5 or higher)
- Dart SDK (3.8.1 or higher)
- Android Studio / Xcode
- Git

## 🔧 Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/Skybyn_APP.git
   cd Skybyn_APP
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## 📱 Platform Setup

### Android
- Minimum SDK: 21
- Target SDK: Latest
- NDK Version: 27.0.12077973
- Camera permissions configured
- Core library desugaring enabled

### iOS
- iOS 12.0+
- Camera permissions configured
- Biometric authentication support

## 🏗️ Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── user.dart
│   ├── post.dart
│   └── comment.dart
├── screens/                  # UI screens
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── profile_screen.dart
│   ├── settings_screen.dart
│   └── qr_scanner_screen.dart
├── services/                 # Business logic
│   ├── auth_service.dart
│   ├── theme_service.dart
│   ├── local_auth_service.dart
│   ├── device_service.dart
│   ├── focus_service.dart
│   ├── post_service.dart
│   ├── comment_service.dart
│   ├── notification_service.dart
│   └── realtime_service.dart
└── widgets/                  # Reusable components
    ├── background_gradient.dart
    ├── custom_app_bar.dart
    ├── custom_bottom_navigation_bar.dart
    ├── post_card.dart
    ├── search_form.dart
    ├── user_menu.dart
    └── custom_snack_bar.dart
```

## 🔐 Configuration

### API Configuration
The app connects to the Skybyn API at `https://api.skybyn.no/`

### Environment Variables
Create a `.env` file in the root directory for environment-specific configurations.

## 🚀 Building for Production

### Android
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

## 📄 License

This project is proprietary software. All rights reserved.

## 🤝 Contributing

This is a private project. For contributions, please contact the development team.

## 📞 Support

For support and questions, please contact the development team.

---

**Skybyn App** - Secure Cloud Storage Solution
