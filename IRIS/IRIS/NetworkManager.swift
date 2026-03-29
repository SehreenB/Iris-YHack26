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
    private static let geminiAPIKeyKey = "iris.network.geminiAPIKey"
    private static let bundledGeminiAPIKey = (Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // MARK: - Published state (observe these in SwiftUI)
    @Published var steps: [String] = []
    @Published var currentGuidanceText: String = ""
    @Published var errorMessage: String?
    @Published var searchErrorMessage: String?
    @Published var phoneVisionErrorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isSearching = false
    @Published var isAnalyzingPhoneFrame = false
    @Published var isStreamConnected: Bool = false
    @Published var serverAddress: String = UserDefaults.standard.string(forKey: serverAddressKey) ?? "172.20.10.19:8000"
    @Published var geminiAPIKey: String = {
        let savedValue = UserDefaults.standard.string(forKey: geminiAPIKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return savedValue.isEmpty ? (bundledGeminiAPIKey ?? "") : savedValue
    }()

    // MARK: - Private
    private var audioPlayer: AVAudioPlayer?
    private var streamTask: URLSessionWebSocketTask?
    private var phoneStreamTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    var websocketTarget: String {
        "ws://\(normalizedServerAddress)/experiment-stream"
    }

    var phoneWebsocketTarget: String {
        "ws://\(normalizedServerAddress)/phone-stream"
    }

    func updateServerAddress(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }
        serverAddress = trimmedValue
        UserDefaults.standard.set(trimmedValue, forKey: Self.serverAddressKey)
    }

    func updateGeminiAPIKey(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        geminiAPIKey = trimmedValue
        UserDefaults.standard.set(trimmedValue, forKey: Self.geminiAPIKeyKey)
    }

    func resetSessionState() {
        steps = []
        currentGuidanceText = ""
        errorMessage = nil
        isStreamConnected = false
    }

    func searchExperiments(query: String, language: AppLanguage = .english) async -> [Experiment] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchErrorMessage = nil
            return []
        }

        guard !geminiAPIKey.isEmpty else {
            searchErrorMessage = nil
            return []
        }

        isSearching = true
        searchErrorMessage = nil
        defer { isSearching = false }

        let subjectList = Subject.allCases.map(\.rawValue).joined(separator: ", ")
        let difficultyList = Difficulty.allCases.map(\.rawValue).joined(separator: ", ")

        let prompt = """
        Find up to 4 real science lab experiments that best match this search query: "\(trimmedQuery)".

        Return only experiments that a student could realistically perform in a lab or classroom.
        Write the experiment names, descriptions, steps, and materials in \(language.promptName).
        Normalize each result into valid JSON with these exact fields:
        - name: string
        - subject: one of [\(subjectList)]
        - difficulty: one of [\(difficultyList)]
        - time: short string like "20 min"
        - description: one sentence
        - steps: array of 3 to 5 short steps
        - materials: array of 3 to 6 short material names

        Return JSON only in this shape:
        { "experiments": [ ... ] }
        """

        let payload = GeminiSearchRequest(
            contents: [
                .init(parts: [.init(text: prompt)])
            ],
            tools: [.init(googleSearch: GeminiGoogleSearchTool())],
            generationConfig: .init(
                responseMimeType: "application/json",
                temperature: 0.2
            )
        )

        do {
            guard let text = try await performGeminiRequest(payload) else {
                searchErrorMessage = "Gemini returned an unreadable search response."
                return []
            }

            let jsonData = Data(text.utf8)
            let searchResults = try JSONDecoder().decode(GeminiSearchResultEnvelope.self, from: jsonData)
            return searchResults.experiments.map { result in
                Experiment(
                    name: result.name,
                    subject: result.subjectValue,
                    difficulty: result.difficultyValue,
                    time: result.time,
                    description: result.description,
                    steps: result.steps,
                    materials: result.materials,
                    isUploaded: false
                )
            }
        } catch {
            searchErrorMessage = "Gemini search error: \(error.localizedDescription)"
            return []
        }
    }

    func analyzePhoneFrame(
        _ frameData: Data,
        experimentName: String,
        experimentType: String,
        currentStep: String,
        materials: [String],
        language: AppLanguage = .english
    ) async -> PhoneVisionAnalysis? {
        guard !geminiAPIKey.isEmpty else { return nil }

        isAnalyzingPhoneFrame = true
        phoneVisionErrorMessage = nil
        defer { isAnalyzingPhoneFrame = false }

        let materialSummary = materials.prefix(5).joined(separator: ", ")
        let prompt = """
        You are IRIS, a real-time AI lab assistant.
        The student is doing the experiment "\(experimentName)" of type "\(experimentType)".
        Current step: "\(currentStep)".
        Relevant materials: \(materialSummary.isEmpty ? "Not provided" : materialSummary).

        Look at this phone camera frame and respond in JSON only:
        {
          "status": "ok" | "warning",
          "action": "advance" | "hold",
          "message": "one short sentence to read aloud",
          "should_store": true
        }

        Rules:
        - Be specific to the current step.
        - If the frame is too dark, blurry, or poorly framed, mention that.
        - If the current step names a specific color, container, or material and the student appears to use the wrong one, set status to "warning" and name the mismatch.
        - If the student appears to be doing the wrong thing, set status to "warning".
        - Use action "advance" only when the current step is clearly complete and the app should move to the next step now.
        - Otherwise use action "hold".
        - Write the message in \(language.promptName).
        - Keep the message under 24 words.
        """

        let payload = GeminiVisionRequest(
            contents: [
                .init(parts: [
                    .init(inlineData: .init(mimeType: "image/jpeg", data: frameData.base64EncodedString())),
                    .init(text: prompt)
                ])
            ],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.2)
        )

        do {
            guard let text = try await performGeminiRequest(payload) else {
                phoneVisionErrorMessage = "Gemini phone vision returned no text."
                return nil
            }
            return try JSONDecoder().decode(PhoneVisionAnalysis.self, from: Data(text.utf8))
        } catch {
            phoneVisionErrorMessage = "Phone vision error: \(error.localizedDescription)"
            return nil
        }
    }

    func answerPhoneQuestion(
        _ question: String,
        experimentName: String,
        currentStep: String,
        materials: [String],
        language: AppLanguage = .english
    ) async -> String? {
        guard !geminiAPIKey.isEmpty else { return nil }

        let materialSummary = materials.prefix(5).joined(separator: ", ")
        let prompt = """
        You are IRIS, a phone-based lab assistant.
        Experiment: "\(experimentName)"
        Current step: "\(currentStep)"
        Materials: \(materialSummary.isEmpty ? "Not provided" : materialSummary)

        Student question: "\(question)"

        Answer in 2 short sentences maximum. Be clear, practical, and specific to the current step.
        Respond in \(language.promptName).
        """

        let payload = GeminiVisionRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(responseMimeType: "text/plain", temperature: 0.3)
        )

        do {
            return try await performGeminiRequest(payload)
        } catch {
            phoneVisionErrorMessage = "Phone Q&A error: \(error.localizedDescription)"
            return nil
        }
    }

    func summarizePhoneExperiment(
        experimentName: String,
        completedSteps: [String],
        warnings: [String],
        language: AppLanguage = .english
    ) async -> String? {
        guard !geminiAPIKey.isEmpty else { return nil }

        let prompt = """
        Summarize this lab session in 3 short sentences.
        Experiment: "\(experimentName)"
        Completed steps: \(completedSteps.joined(separator: "; "))
        Warnings: \(warnings.isEmpty ? "None" : warnings.joined(separator: "; "))

        Mention what the student accomplished, one observation or caution, and one encouraging closing sentence.
        Respond in \(language.promptName).
        """

        let payload = GeminiVisionRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(responseMimeType: "text/plain", temperature: 0.3)
        )

        do {
            return try await performGeminiRequest(payload)
        } catch {
            phoneVisionErrorMessage = "Phone summary error: \(error.localizedDescription)"
            return nil
        }
    }

    func testConnection() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseHTTP)/") else {
            errorMessage = "Invalid server URL."
            return false
        }

        do {
            let (_, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                errorMessage = "Backend responded with an unexpected status."
                return false
            }
            return true
        } catch {
            errorMessage = serverUnreachableMessage(error)
            return false
        }
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

        disconnectStream()
        streamTask = urlSession.webSocketTask(with: url)
        streamTask?.resume()
        isStreamConnected = false
        errorMessage       = nil
        receiveNextMessage()
    }

    func disconnectStream() {
        streamTask?.cancel(with: .goingAway, reason: nil)
        streamTask        = nil
        isStreamConnected = false
    }

    func connectPhoneStream() {
        guard let url = URL(string: phoneWebsocketTarget) else {
            errorMessage = "Invalid phone WebSocket URL."
            return
        }

        disconnectPhoneStream()
        phoneStreamTask = urlSession.webSocketTask(with: url)
        phoneStreamTask?.resume()
        isStreamConnected = false
        errorMessage = nil
        receiveNextPhoneMessage()
    }

    func disconnectPhoneStream() {
        phoneStreamTask?.cancel(with: .goingAway, reason: nil)
        phoneStreamTask = nil
        isStreamConnected = false
    }

    func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func sendPhoneFrame(_ frameData: Data, experimentType: String, currentStep: String) async {
        guard let phoneStreamTask else { return }
        let payload = PhoneFramePayload(
            experimentType: experimentType,
            currentStep: currentStep,
            frameBase64: frameData.base64EncodedString()
        )

        do {
            let encoded = try JSONEncoder().encode(payload)
            guard let jsonString = String(data: encoded, encoding: .utf8) else {
                errorMessage = "Phone frame payload could not be encoded."
                return
            }
            try await phoneStreamTask.send(.string(jsonString))
        } catch {
            isStreamConnected = false
            errorMessage = serverUnreachableMessage(error)
        }
    }

    // MARK: - Private helpers

    private func receiveNextMessage() {
        streamTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.isStreamConnected = true
                    self.handleStreamMessage(message)
                    self.receiveNextMessage()          // keep listening

                case .failure(let error):
                    self.isStreamConnected = false
                    self.errorMessage = self.serverUnreachableMessage(error)
                }
            }
        }
    }

    private func receiveNextPhoneMessage() {
        phoneStreamTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.isStreamConnected = true
                    self.handleStreamMessage(message)
                    self.receiveNextPhoneMessage()

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
            configureAudioSession()
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
                options: [.duckOthers]
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

    private func performGeminiRequest<T: Encodable>(_ payload: T) async throws -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "IRIS.Gemini", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gemini request failed."])
        }

        let decoded = try JSONDecoder().decode(GeminiSearchAPIResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first(where: { $0.text != nil })?.text
    }
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

private struct PhoneFramePayload: Encodable {
    let experimentType: String
    let currentStep: String
    let frameBase64: String

    enum CodingKeys: String, CodingKey {
        case experimentType = "experiment_type"
        case currentStep = "current_step"
        case frameBase64 = "frame_base64"
    }
}

private struct GeminiSearchRequest: Encodable {
    let contents: [GeminiContent]
    let tools: [GeminiTool]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    var text: String?
    var inlineData: GeminiInlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(inlineData: GeminiInlineData) {
        self.text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct GeminiInlineData: Encodable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiTool: Encodable {
    let googleSearch: GeminiGoogleSearchTool?

    enum CodingKeys: String, CodingKey {
        case googleSearch = "google_search"
    }
}

private struct GeminiGoogleSearchTool: Encodable {}

private struct GeminiGenerationConfig: Encodable {
    let responseMimeType: String
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case responseMimeType = "responseMimeType"
        case temperature
    }
}

private struct GeminiVisionRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiSearchAPIResponse: Decodable {
    let candidates: [GeminiSearchCandidate]
}

private struct GeminiSearchCandidate: Decodable {
    let content: GeminiSearchContent
}

private struct GeminiSearchContent: Decodable {
    let parts: [GeminiSearchTextPart]
}

private struct GeminiSearchTextPart: Decodable {
    let text: String?
}

struct PhoneVisionAnalysis: Decodable {
    let status: String
    let action: String?
    let message: String
    let shouldStore: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case action
        case message
        case shouldStore = "should_store"
    }

    var isWarning: Bool {
        status.caseInsensitiveCompare("warning") == .orderedSame
    }

    var shouldAdvance: Bool {
        action?.caseInsensitiveCompare("advance") == .orderedSame
    }
}

private struct GeminiSearchResultEnvelope: Decodable {
    let experiments: [GeminiExperimentResult]
}

private struct GeminiExperimentResult: Decodable {
    let name: String
    let subject: String
    let difficulty: String
    let time: String
    let description: String
    let steps: [String]
    let materials: [String]

    var subjectValue: Subject {
        Subject.allCases.first { $0.rawValue.caseInsensitiveCompare(subject) == .orderedSame } ?? .chemistry
    }

    var difficultyValue: Difficulty {
        Difficulty.allCases.first { $0.rawValue.caseInsensitiveCompare(difficulty) == .orderedSame } ?? .beginner
    }
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
