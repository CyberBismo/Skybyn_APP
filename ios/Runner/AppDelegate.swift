import Flutter
import UIKit
import AudioToolbox
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let SYSTEM_SOUNDS_CHANNEL = "no.skybyn.app/system_sounds"
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up method channel for system sounds
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    let systemSoundsChannel = FlutterMethodChannel(
      name: SYSTEM_SOUNDS_CHANNEL,
      binaryMessenger: controller.binaryMessenger
    )
    
    systemSoundsChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      
      switch call.method {
      case "getSystemSounds":
        result(self.getSystemSounds())
      case "playSound":
        if let args = call.arguments as? [String: Any],
           let soundId = args["soundId"] as? String {
          self.playSystemSound(soundId: soundId)
          result(true)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Sound ID is required", details: nil))
        }
      case "playCustomSound":
        if let args = call.arguments as? [String: Any],
           let filePath = args["filePath"] as? String {
          self.playCustomSound(filePath: filePath)
          result(true)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "File path is required", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func getSystemSounds() -> [[String: String]] {
    // iOS doesn't provide a direct API to list all system sounds
    // We'll provide a list of common iOS system sound IDs
    let systemSoundIds: [UInt32] = [
      1000, // New Mail
      1001, // Mail Sent
      1002, // Voicemail
      1003, // Received Message
      1004, // Sent Message
      1005, // Calendar Alert
      1006, // Low Power
      1007, // SMS Received
      1008, // SMS Sent
      1009, // Alert Tone
      1010, // Anticipate
      1011, // Bloom
      1012, // Calypso
      1013, // Choo Choo
      1014, // Descent
      1015, // Fanfare
      1016, // Ladder
      1017, // Minuet
      1018, // News Flash
      1019, // Noir
      1020, // Sherwood Forest
      1021, // Spell
      1022, // Suspense
      1023, // Telegraph
      1024, // Tiptoes
      1025, // Typewriters
      1026, // Update
      1050, // Mailbox
      1051, // Mail Sent
      1052, // Tweet Sent
      1053, // Anticipate
      1054, // Bloom
      1055, // Calypso
      1056, // Choo Choo
      1057, // Descent
      1058, // Fanfare
      1059, // Ladder
      1060, // Minuet
      1061, // News Flash
      1062, // Noir
      1063, // Sherwood Forest
      1064, // Spell
      1065, // Suspense
      1066, // Telegraph
      1067, // Tiptoes
      1068, // Typewriters
      1069, // Update
      1070, // Default (Notification)
    ]
    
    var sounds: [[String: String]] = []
    
    // Add default option
    sounds.append([
      "id": "default",
      "title": "Default",
      "uri": "default"
    ])
    
    // Add system sounds
    for soundId in systemSoundIds {
      let title = getSystemSoundName(soundId: soundId)
      sounds.append([
        "id": "ios_\(soundId)",
        "title": title,
        "uri": "\(soundId)"
      ])
    }
    
    return sounds
  }
  
  private func getSystemSoundName(soundId: UInt32) -> String {
    // Map common iOS system sound IDs to readable names
    let soundNames: [UInt32: String] = [
      1000: "New Mail",
      1001: "Mail Sent",
      1002: "Voicemail",
      1003: "Received Message",
      1004: "Sent Message",
      1005: "Calendar Alert",
      1006: "Low Power",
      1007: "SMS Received",
      1008: "SMS Sent",
      1009: "Alert Tone",
      1010: "Anticipate",
      1011: "Bloom",
      1012: "Calypso",
      1013: "Choo Choo",
      1014: "Descent",
      1015: "Fanfare",
      1016: "Ladder",
      1017: "Minuet",
      1018: "News Flash",
      1019: "Noir",
      1020: "Sherwood Forest",
      1021: "Spell",
      1022: "Suspense",
      1023: "Telegraph",
      1024: "Tiptoes",
      1025: "Typewriters",
      1026: "Update",
      1050: "Mailbox",
      1051: "Mail Sent",
      1052: "Tweet Sent",
      1070: "Default Notification"
    ]
    
    return soundNames[soundId] ?? "System Sound \(soundId)"
  }
  
  private func playSystemSound(soundId: String) {
    if soundId == "default" {
      // Play default notification sound
      AudioServicesPlaySystemSound(1007) // SMS Received is commonly used as default
    } else if soundId.hasPrefix("ios_") {
      // Extract sound ID from "ios_XXXX" format
      let idString = String(soundId.dropFirst(4))
      if let soundIdValue = UInt32(idString) {
        AudioServicesPlaySystemSound(soundIdValue)
      }
    } else if let soundIdValue = UInt32(soundId) {
      // Direct sound ID
      AudioServicesPlaySystemSound(soundIdValue)
    }
  }
  
  private func playCustomSound(filePath: String) {
    do {
      let url = URL(fileURLWithPath: filePath)
      
      // Check if file exists
      guard FileManager.default.fileExists(atPath: filePath) else {
        // Fallback to default
        AudioServicesPlaySystemSound(1007)
        return
      }
      
      // Use AVAudioPlayer for custom sounds
      var audioPlayer: AVAudioPlayer?
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.prepareToPlay()
      audioPlayer?.play()
      
      // Note: audioPlayer will be deallocated when it finishes playing
    } catch {
      // Fallback to default on error
      AudioServicesPlaySystemSound(1007)
    }
  }
}
