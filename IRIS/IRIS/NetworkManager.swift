//
//  NetworkManager.swift
//  IRIS
//
//  Created by betul cetintas on 2026-03-28.
//

//
//  NetworkManager.swift
//  IRIS
//
//  Handles REST + WebSocket communication with the backend server.
//  Drop this file into your Xcode project — no other files need to change
//  to get audio + guidance working. See integration notes at the bottom.
//

import AVFoundation
import Combine
import Foundation

// ─── NetworkManager ───────────────────────────────────────────────────────────
@MainActor
final class NetworkManager: NSObject, ObservableObject {
    private static let serverAddressKey = "iris.network.serverAddress"

    // MARK: - Published state (observe these in SwiftUI)
    @Published var steps: [String] = []
    @Published var currentGuidanceText: String = ""
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isStreamConnected: Bool = false
    @Published var serverAddress: String = UserDefaults.standard.string(forKey: serverAddressKey) ?? "10.65.102.9:8000"

    // MARK: - Private
    private var audioPlayer: AVAudioPlayer?
    private var streamTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        configureAudioSession()
    }

    var websocketTarget: String {
        "ws://\(normalizedServerAddress)/experiment-stream"
    }

    func updateServerAddress(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }
        serverAddress = trimmedValue
        UserDefaults.standard.set(trimmedValue, forKey: Self.serverAddressKey)
    }

    // MARK: - REST: Start experiment
    /// Sends POST /start-experiment with {"experiment_type": type}
    /// Returns the steps array from the response.
    func startExperiment(type: String) async -> [String] {
        isLoading   = true
        errorMessage = nil

        defer { isLoading = false }

        guard let url = URL(string: "\(baseHTTP)/start-experiment") else {
            errorMessage = "Invalid server URL — check SERVER_IP and SERVER_PORT."
            return []
        }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(["experiment_type": type])
            let (data, response) = try await urlSession.data(for: request)

            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                errorMessage = "Server returned an error — is Sehreen's backend running?"
                return []
            }

            // Response shape: { "steps": ["step 1", "step 2", ...] }
            if let json = try? JSONDecoder().decode(StartExperimentResponse.self, from: data) {
                steps = json.steps
                return json.steps
            }

            // Fallback: try generic JSON dict
            if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawSteps = raw["steps"] as? [String] {
                steps = rawSteps
                return rawSteps
            }

            errorMessage = "Unexpected response from server."
            return []

        } catch {
            errorMessage = serverUnreachableMessage(error)
            return []
        }
    }

    // MARK: - REST: Advance step
    /// Sends POST /advance-step (no body required).
    func advanceStep() {
        Task {
            guard let url = URL(string: "\(baseHTTP)/advance-step") else { return }
            var request        = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody   = try? JSONEncoder().encode([String: String]())

            do {
                let (_, response) = try await urlSession.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
                    errorMessage = "advanceStep failed — server returned \(http.statusCode)."
                }
            } catch {
                errorMessage = serverUnreachableMessage(error)
            }
        }
    }

    func askQuestion(_ question: String) async -> AskQuestionResponse? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseHTTP)/ask-question") else {
            errorMessage = "Invalid server URL."
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(AskQuestionRequest(question: question))
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                errorMessage = "Question request failed."
                return nil
            }

            let payload = try JSONDecoder().decode(AskQuestionResponse.self, from: data)
            if let error = payload.error, !error.isEmpty {
                errorMessage = error
                return nil
            }

            if let answerText = payload.answerText, !answerText.isEmpty {
                currentGuidanceText = answerText
            }
            if let audioBase64 = payload.audioBase64 {
                playAudioBase64(audioBase64)
            }
            return payload
        } catch {
            errorMessage = serverUnreachableMessage(error)
            return nil
        }
    }

    func endExperiment() async -> EndExperimentResponse? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseHTTP)/end-experiment") else {
            errorMessage = "Invalid server URL."
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([String: String]())

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                errorMessage = "End experiment request failed."
                return nil
            }

            let payload = try JSONDecoder().decode(EndExperimentResponse.self, from: data)
            if let error = payload.error, !error.isEmpty {
                errorMessage = error
                return nil
            }

            if let summaryText = payload.summaryText, !summaryText.isEmpty {
                currentGuidanceText = summaryText
            }
            if let audioBase64 = payload.audioBase64 {
                playAudioBase64(audioBase64)
            }
            return payload
        } catch {
            errorMessage = serverUnreachableMessage(error)
            return nil
        }
    }

    // MARK: - WebSocket: Experiment stream
    /// Connects to ws://SERVER_IP:SERVER_PORT/experiment-stream.
    /// Listens continuously; each message carries audio_base64 + text.
    func connectStream() {
        guard let url = URL(string: websocketTarget) else {
            errorMessage = "Invalid WebSocket URL."
            return
        }

        streamTask = urlSession.webSocketTask(with: url)
        streamTask?.resume()
        isStreamConnected = true
        errorMessage       = nil
        receiveNextMessage()
    }

    func disconnectStream() {
        streamTask?.cancel(with: .goingAway, reason: nil)
        streamTask        = nil
        isStreamConnected = false
    }

    // MARK: - Private helpers

    private func receiveNextMessage() {
        streamTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.handleStreamMessage(message)
                    self.receiveNextMessage()          // keep listening

                case .failure(let error):
                    self.isStreamConnected = false
                    self.errorMessage = self.serverUnreachableMessage(error)
                }
            }
        }
    }

    private func handleStreamMessage(_ message: URLSessionWebSocketTask.Message) {
        var jsonData: Data?

        switch message {
        case .string(let text):
            jsonData = text.data(using: .utf8)
        case .data(let data):
            jsonData = data
        @unknown default:
            return
        }

        guard let jsonData,
              let payload = try? JSONDecoder().decode(StreamPayload.self, from: jsonData) else {
            return
        }

        // Update guidance text so UI can display it
        if let text = payload.text, !text.isEmpty {
            currentGuidanceText = text
        }

        // Decode + play audio
        if let b64 = payload.audio_base64,
           let audioData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
            playAudio(data: audioData)
        }
    }

    private func playAudioBase64(_ base64String: String) {
        guard let audioData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            errorMessage = "Audio payload could not be decoded."
            return
        }
        playAudio(data: audioData)
    }

    private func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            // Audio decode failed — guidance text is still shown
            errorMessage = "Audio playback error: \(error.localizedDescription)"
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetoothHFP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("IRIS AudioSession setup failed: \(error)")
        }
    }

    private func serverUnreachableMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.code == NSURLErrorCannotConnectToHost || ns.code == NSURLErrorNetworkConnectionLost {
            return "Cannot reach server at \(normalizedServerAddress). Check that Sehreen's backend is running and you're on the same hotspot."
        }
        return "Network error: \(error.localizedDescription)"
    }

    private var normalizedServerAddress: String {
        serverAddress
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
            .replacingOccurrences(of: "wss://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var baseHTTP: String { "http://\(normalizedServerAddress)" }
    private var baseWS: String { "ws://\(normalizedServerAddress)" }
}

// ─── Codable response models ──────────────────────────────────────────────────
private struct StartExperimentResponse: Decodable {
    let steps: [String]
}

private struct AskQuestionRequest: Encodable {
    let question: String
}

struct AskQuestionResponse: Decodable {
    let answerText: String?
    let audioBase64: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case answerText = "answer_text"
        case audioBase64 = "audio_base64"
        case error
    }
}

struct EndExperimentResponse: Decodable {
    let summaryText: String?
    let audioBase64: String?
    let stepsCompleted: Int?
    let totalSteps: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case summaryText = "summary_text"
        case audioBase64 = "audio_base64"
        case stepsCompleted = "steps_completed"
        case totalSteps = "total_steps"
        case error
    }
}

private struct StreamPayload: Decodable {
    let audio_base64: String?
    let text: String?
}

// ─── Integration notes ────────────────────────────────────────────────────────
// In your AssistantScreen or AppSession, add:
//
//   @StateObject var networkManager = NetworkManager()
//
// Then wire buttons like this:
//
//   // When experiment starts:
//   Task {
//       let steps = await networkManager.startExperiment(type: "titration")
//       // steps is [String] — use these or pass to your existing AppSession
//   }
//   networkManager.connectStream()   // starts WebSocket, audio plays automatically
//
//   // When "Confirm step" is tapped:
//   networkManager.advanceStep()
//
//   // Display guidance text:
//   Text(networkManager.currentGuidanceText)
//
//   // Show errors:
//   if let error = networkManager.errorMessage {
//       Text(error).foregroundStyle(.red)
//   }
//
//   // On session end:
//   networkManager.disconnectStream()
//
// Day-of IP change:
//   At the top of this file, change:
//     let SERVER_IP = "127.0.0.1"
//   to Sehreen's LAN IP, e.g.:
//     let SERVER_IP = "192.168.4.23"
