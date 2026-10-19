import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVSpeechSynthesizerDelegate {
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var ttsChannel: FlutterMethodChannel?
  private var pendingTtsResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    speechSynthesizer.delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "mentora/tts",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    ttsChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleTtsCall(call, result: result)
    }
  }

  private func handleTtsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      guard let args = call.arguments as? [String: Any],
            let text = (args["text"] as? String)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
        result(FlutterError(code: "INVALID_INPUT", message: "text is required", details: nil))
        return
      }
      let languageCode = (args["language"] as? String) ?? "en"
      speak(text: text, languageCode: languageCode, result: result)

    case "stop":
      stopSpeaking()
      result(true)

    case "isLanguageAvailable":
      let args = call.arguments as? [String: Any]
      let languageCode = (args?["language"] as? String) ?? "en"
      result(ttsVoice(for: languageCode) != nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func speak(text: String, languageCode: String, result: @escaping FlutterResult) {
    guard let voice = ttsVoice(for: languageCode) else {
      result(
        FlutterError(
          code: "TTS_LANGUAGE_UNAVAILABLE",
          message: "No offline voice is installed for '\(languageCode)'.",
          details: nil
        )
      )
      return
    }

    if let pending = pendingTtsResult {
      pendingTtsResult = nil
      pending(false)
    }
    if speechSynthesizer.isSpeaking {
      speechSynthesizer.stopSpeaking(at: .immediate)
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try session.setActive(true, options: [])
    } catch {
      // Speech still works without an explicitly configured audio session.
    }

    pendingTtsResult = result
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 1.0
    utterance.volume = 1.0
    speechSynthesizer.speak(utterance)
  }

  private func stopSpeaking() {
    speechSynthesizer.stopSpeaking(at: .immediate)
    deactivateAudioSession()
    if let pending = pendingTtsResult {
      pendingTtsResult = nil
      pending(false)
    }
  }

  private func deactivateAudioSession() {
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: [.notifyOthersOnDeactivation]
    )
  }

  private func ttsVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
    let normalized = languageCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let base = normalized.split(separator: "-").first.map(String.init) ?? normalized

    let preferredTag: String
    if normalized.contains("-") {
      preferredTag = normalized
    } else {
      switch base {
      case "en": preferredTag = "en-IN"
      case "hi": preferredTag = "hi-IN"
      case "kn": preferredTag = "kn-IN"
      default: preferredTag = normalized
      }
    }

    if let voice = AVSpeechSynthesisVoice(language: preferredTag) {
      return voice
    }
    if let voice = AVSpeechSynthesisVoice(language: base) {
      return voice
    }
    if base == "en" {
      return AVSpeechSynthesisVoice(language: "en-US")
    }
    return nil
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    guard let pending = pendingTtsResult else { return }
    pendingTtsResult = nil
    deactivateAudioSession()
    pending(true)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    guard let pending = pendingTtsResult else { return }
    pendingTtsResult = nil
    deactivateAudioSession()
    pending(false)
  }
}
