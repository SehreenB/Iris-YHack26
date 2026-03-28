//
//  AppServices.swift
//  IRIS
//

import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class CameraManager: NSObject, ObservableObject {
    private let sessionQueue = DispatchQueue(label: "iris.camera.session")

    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isSessionRunning = false
    @Published var errorMessage: String?
    @Published var selectedPosition: AVCaptureDevice.Position = .back

    nonisolated let session = AVCaptureSession()

    func requestPermissionIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            return granted
        default:
            errorMessage = "Camera access is not available."
            return false
        }
    }

    func startSession(position: AVCaptureDevice.Position = .back) {
        Task {
            let granted = await requestPermissionIfNeeded()
            guard granted else { return }
            selectedPosition = position

            do {
                try await configureSession(position: position)
                sessionQueue.async { [weak self] in
                    guard let self else { return }
                    guard !self.session.isRunning else { return }
                    self.session.startRunning()
                    Task { @MainActor in
                        self.isSessionRunning = self.session.isRunning
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    private func configureSession(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "IRIS", code: -1))
                    return
                }

                do {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high

                    for input in self.session.inputs {
                        self.session.removeInput(input)
                    }

                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                        throw NSError(domain: "IRIS", code: 404, userInfo: [NSLocalizedDescriptionKey: "No camera device found."])
                    }

                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else {
                        throw NSError(domain: "IRIS", code: 405, userInfo: [NSLocalizedDescriptionKey: "Unable to attach camera input."])
                    }

                    self.session.addInput(input)
                    self.session.commitConfiguration()

                    Task { @MainActor in
                        self.selectedPosition = position
                        self.errorMessage = nil
                    }
                    continuation.resume()
                } catch {
                    self.session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
final class BackendManager: ObservableObject {
    private static let backendURLKey = "iris.backend.baseURL"

    @Published var connectionStatus = "Disconnected"
    @Published var latestGuidance = ""
    @Published var latestReportSummary = ""
    @Published var baseURLString: String = UserDefaults.standard.string(forKey: backendURLKey) ?? ""
    @Published var lastErrorMessage: String?
    @Published var sessionID: String?

    func connect(mode: AppMode) {
        connectionStatus = mode == .demo ? "Demo relay" : (baseURLString.isEmpty ? "URL missing" : "Configured")
    }

    func disconnect() {
        connectionStatus = "Disconnected"
        sessionID = nil
    }

    func updateBaseURL(_ value: String) {
        baseURLString = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(baseURLString, forKey: Self.backendURLKey)
    }

    func startSession(for experiment: Experiment, mode: AppMode, cameraSource: String) {
        connect(mode: mode)
        latestGuidance = mode == .demo ? "Demo mode active for \(experiment.name)." : "Preparing live backend session for \(experiment.name)."
        sessionID = nil

        guard mode == .live else { return }

        Task {
            do {
                let response = try await createSession(for: experiment, cameraSource: cameraSource)
                await MainActor.run {
                    self.sessionID = response.sessionID
                    self.latestGuidance = response.guidance
                    self.connectionStatus = response.status.capitalized
                    self.lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Error"
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func sendTranscript(_ text: String, experiment: Experiment, currentStepIndex: Int) async throws -> String {
        let currentStep = experiment.steps[min(max(currentStepIndex - 1, 0), max(experiment.steps.count - 1, 0))]
        let decoded: BackendQuestionResponse = try await post(
            path: sessionID.map { "sessions/\($0)/qa" } ?? "qa",
            body: BackendQuestionRequest(
                experimentName: experiment.name,
                subject: experiment.subject.rawValue,
                currentStepIndex: currentStepIndex,
                currentStep: currentStep,
                question: text,
                materials: experiment.materials,
                sessionId: sessionID
            )
        )
        let answer = decoded.answer ?? decoded.response ?? decoded.message ?? decoded.text ?? ""
        guard !answer.isEmpty else {
            throw NSError(domain: "IRIS", code: 422, userInfo: [NSLocalizedDescriptionKey: "Backend returned an empty answer."])
        }

        latestGuidance = answer
        lastErrorMessage = nil
        connectionStatus = decoded.status?.capitalized ?? "Connected"
        if let remoteSessionID = decoded.sessionID, !remoteSessionID.isEmpty {
            sessionID = remoteSessionID
        }
        return answer
    }

    func finalizeReport(using report: LabReport) {
        latestReportSummary = report.findings.first ?? "Report ready."
        guard let sessionID else { return }

        Task {
            do {
                let response: BackendCompleteSessionResponse = try await post(
                    path: "sessions/\(sessionID)/complete",
                    body: BackendCompleteSessionRequest(
                        procedure: report.procedure,
                        observations: report.observations,
                        errors: report.errors,
                        findings: report.findings,
                        suggestions: report.suggestions
                    )
                )
                await MainActor.run {
                    self.latestReportSummary = response.summary
                    self.connectionStatus = response.status.capitalized
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                    self.connectionStatus = "Error"
                }
            }
        }
    }

    fileprivate func sendEvent(type: BackendEventType, message: String) {
        guard let sessionID else { return }

        Task {
            do {
                let _: BackendStatusResponse = try await post(
                    path: "sessions/\(sessionID)/events",
                    body: BackendSessionEventRequest(type: type, message: message)
                )
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func createSession(for experiment: Experiment, cameraSource: String) async throws -> BackendStartSessionResponse {
        try await post(
            path: "sessions/start",
            body: BackendStartSessionRequest(
                experimentName: experiment.name,
                subject: experiment.subject.rawValue,
                difficulty: experiment.difficulty.rawValue,
                time: experiment.time,
                description: experiment.description,
                steps: experiment.steps,
                materials: experiment.materials,
                cameraSource: cameraSource
            )
        )
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(path: String, body: RequestBody) async throws -> ResponseBody {
        guard !baseURLString.isEmpty, let baseURL = URL(string: baseURLString) else {
            throw NSError(domain: "IRIS", code: 400, userInfo: [NSLocalizedDescriptionKey: "Backend URL is missing."])
        }

        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw NSError(domain: "IRIS", code: 500, userInfo: [NSLocalizedDescriptionKey: "Backend request failed."])
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }
}

@MainActor
final class SpeechCoordinator: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    @Published var isListening = false
    @Published var liveTranscript = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var microphoneGranted = false
    @Published var errorMessage: String?

    func requestPermissionsIfNeeded() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = speechStatus

        let micGranted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        microphoneGranted = micGranted

        let granted = speechStatus == .authorized && micGranted
        errorMessage = granted ? nil : "Speech recognition permission is required."
        return granted
    }

    func startListening() {
        Task {
            let granted = await requestPermissionsIfNeeded()
            guard granted else { return }

            do {
                recognitionTask?.cancel()
                recognitionTask = nil
                recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                guard let recognitionRequest else { return }
                recognitionRequest.shouldReportPartialResults = true

                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                    self?.recognitionRequest?.append(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()

                liveTranscript = ""
                isListening = true
                errorMessage = nil

                recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let result {
                            self.liveTranscript = result.bestTranscription.formattedString
                        }
                        if let error {
                            self.errorMessage = error.localizedDescription
                            self.stopAudioCapture()
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                stopAudioCapture()
            }
        }
    }

    func stopListening() -> String {
        let finalTranscript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudioCapture()
        return finalTranscript
    }

    private func stopAudioCapture() {
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class AppSession: ObservableObject {
    private static let experimentsStorageKey = "iris.saved.experiments"

    @Published var activeScreen: Screen = .landing
    @Published var currentExperiment: Experiment?
    @Published var experiments: [Experiment]
    @Published var showUploadSheet = false
    @Published var isLive = false
    @Published var showSplash = true
    @Published var onboardingStep = 0

    @Published var appMode: AppMode = .demo
    @Published var currentStepIndex = 1
    @Published var currentStatus: GuidanceStatus = .watching
    @Published var guidanceFeed: [GuidanceItem] = []
    @Published var transcript = ""
    @Published var lastErrorMessage: String?
    @Published var cameraSource = "Phone camera · Rear"
    @Published var isUsingExternalCamera = false
    @Published var connectionStatuses: [ConnectionStatus] = [
        .init(label: "Camera", value: "Ready", color: IrisPalette.viridian),
        .init(label: "AI", value: "Demo", color: IrisPalette.flame),
        .init(label: "Audio", value: "Standby", color: IrisPalette.coolAqua)
    ]
    @Published var reportStatus: ReportBuildStatus = .building
    @Published var generatedReport = LabReport(
        procedure: [],
        observations: "No session data captured yet.",
        errors: [],
        findings: [],
        suggestions: []
    )

    // ── NetworkManager — Sehreen's backend ────────────────────────────────────
    let networkManager = NetworkManager()

    let backendManager = BackendManager()
    let speechCoordinator = SpeechCoordinator()
    let cameraManager = CameraManager()

    init() {
        experiments = Self.loadExperiments()
    }

    // ── Live session start — follows Sehreen's /start-experiment + WS flow ──
    func startLiveSession(for experiment: Experiment) {
        currentExperiment = experiment
        currentStepIndex = 1
        currentStatus = .watching
        transcript = ""
        lastErrorMessage = nil
        if !isUsingExternalCamera {
            updateCameraSource(position: cameraManager.selectedPosition)
        }
        isLive = true
        reportStatus = .building
        guidanceFeed = []

        if appMode == .live {
            Task {
                let backendSteps = await networkManager.startExperiment(
                    type: experiment.backendType
                )
                await MainActor.run {
                    if !backendSteps.isEmpty {
                        var liveExperiment = experiment
                        liveExperiment.steps = backendSteps
                        currentExperiment = liveExperiment
                        guidanceFeed.append(GuidanceItem(
                            type: .confirmed,
                            message: "Loaded \(backendSteps.count) steps from Sehreen's backend."
                        ))
                    }
                    if let err = networkManager.errorMessage {
                        flagIssue(err)
                    } else {
                        syncConnectionStatuses(audio: "Streaming")
                        rebuildReport()
                    }
                }
            }
            networkManager.connectStream()
            syncConnectionStatuses(audio: "Streaming")
        } else {
            backendManager.startSession(for: experiment, mode: appMode, cameraSource: cameraSource)
            syncConnectionStatuses(audio: "Ready")
        }

        if isUsingExternalCamera {
            cameraManager.stopSession()
        } else {
            cameraManager.startSession(position: cameraManager.selectedPosition)
        }

        rebuildReport()
    }

    func acknowledgeError() {
        currentStatus = .watching
        lastErrorMessage = nil
        rebuildReport()
    }

    func beginListening() {
        guard isLive else { return }
        speechCoordinator.startListening()
        syncConnectionStatuses(audio: "Listening")
    }

    @discardableResult
    func completeListeningTurn() -> String {
        let finalTranscript = speechCoordinator.stopListening()
        if !finalTranscript.isEmpty {
            transcript = finalTranscript
        }
        syncConnectionStatuses(audio: "Ready")
        return finalTranscript
    }

    func submitQuestion(_ question: String) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }

        transcript = trimmedQuestion
        guidanceFeed.append(GuidanceItem(type: .qa, message: "Q: \(transcript)"))

        if appMode == .demo {
            guard let experiment = currentExperiment else { return }
            let response = localGuidance(for: trimmedQuestion, experiment: experiment)
            guidanceFeed.append(GuidanceItem(type: .qa, message: response))
            syncConnectionStatuses(audio: "Ready")
            rebuildReport()
            return
        }

        syncConnectionStatuses(audio: "Processing")
        Task {
            let response = await networkManager.askQuestion(trimmedQuestion)
            await MainActor.run {
                if let answerText = response?.answerText, !answerText.isEmpty {
                    self.guidanceFeed.append(GuidanceItem(type: .qa, message: answerText))
                    self.syncConnectionStatuses(audio: "Streaming")
                } else if let error = networkManager.errorMessage {
                    self.flagIssue(error)
                    self.syncConnectionStatuses(audio: "Error")
                }
                self.rebuildReport()
            }
        }
    }

    // Advance step — also tells Sehreen's backend in live mode
    func advanceCurrentStep() {
        guard let experiment = currentExperiment, currentStepIndex <= experiment.steps.count else { return }

        let completedStep = experiment.steps[currentStepIndex - 1]
        guidanceFeed.append(GuidanceItem(type: .confirmed, message: "Completed step \(currentStepIndex): \(completedStep)"))

        if appMode == .live {
            networkManager.advanceStep()
        }

        if currentStepIndex < experiment.steps.count {
            currentStepIndex += 1
            currentStatus = .watching
        } else {
            guidanceFeed.append(GuidanceItem(type: .confirmed, message: "Experiment flow completed. Review the report for final notes."))
        }

        rebuildReport()
    }

    func flagIssue(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        currentStatus = .error
        lastErrorMessage = trimmedMessage
        guidanceFeed.append(GuidanceItem(type: .warning, message: trimmedMessage))
        rebuildReport()
    }

    func endLiveSession() {
        isLive = false
        reportStatus = .complete
        if appMode == .live {
            Task {
                let response = await networkManager.endExperiment()
                await MainActor.run {
                    if let summaryText = response?.summaryText, !summaryText.isEmpty {
                        self.guidanceFeed.append(GuidanceItem(type: .confirmed, message: summaryText))
                        self.generatedReport.observations = summaryText
                        self.generatedReport.findings = [
                            "Completed \(response?.stepsCompleted ?? self.currentStepIndex) of \(response?.totalSteps ?? self.currentExperiment?.steps.count ?? self.currentStepIndex) steps",
                            summaryText
                        ]
                    }
                    self.networkManager.disconnectStream()
                    self.cameraManager.stopSession()
                    self.syncConnectionStatuses(camera: "Paused", audio: "Saved")
                    self.rebuildReport()
                }
            }
        } else {
            backendManager.disconnect()
            cameraManager.stopSession()
            syncConnectionStatuses(camera: "Paused", audio: "Saved")
            rebuildReport()
        }
    }

    func completeReportBuild() {
        reportStatus = .complete
        if appMode == .demo {
            backendManager.finalizeReport(using: generatedReport)
        }
        syncConnectionStatuses(audio: "Synced")
    }

    func prepareCamera(position: AVCaptureDevice.Position) {
        isUsingExternalCamera = false
        cameraManager.startSession(position: position)
        updateCameraSource(position: position)
        syncConnectionStatuses(audio: speechCoordinator.isListening ? "Listening" : "Ready")
    }

    func updateCameraSource(position: AVCaptureDevice.Position) {
        isUsingExternalCamera = false
        cameraSource = "Phone camera · \(position == .front ? "Front" : "Rear")"
    }

    func useExternalCameraSource() {
        isUsingExternalCamera = true
        cameraManager.stopSession()
        cameraSource = "Smart glasses · External stream"
        syncConnectionStatuses(camera: "External", audio: speechCoordinator.isListening ? "Listening" : "Ready")
    }

    func updateAppMode(_ mode: AppMode) {
        appMode = mode
        backendManager.connect(mode: mode)
        syncConnectionStatuses(audio: speechCoordinator.isListening ? "Listening" : "Ready")
    }

    func importExperiment(
        name: String,
        subject: Subject,
        difficulty: Difficulty,
        method: String,
        rawText: String
    ) {
        let experiment = parseExperiment(
            from: rawText,
            name: name,
            subject: subject,
            difficulty: difficulty,
            method: method
        )
        experiments.insert(experiment, at: 0)
        currentExperiment = experiment
        saveExperiments()
        showUploadSheet = false
        activeScreen = .experiment
    }

    func clearExperimentHistory() {
        experiments.removeAll()
        currentExperiment = nil
        generatedReport = LabReport(procedure: [], observations: "No session data captured yet.", errors: [], findings: [], suggestions: [])
        guidanceFeed.removeAll()
        saveExperiments()
        activeScreen = .home
    }

    private func parseExperiment(
        from rawText: String,
        name: String,
        subject: Subject,
        difficulty: Difficulty,
        method: String
    ) -> Experiment {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsedSteps = lines
            .filter { line in
                guard let firstCharacter = line.first else { return false }
                return firstCharacter.isNumber || line.lowercased().hasPrefix("step")
            }
            .map { line in
                line.replacingOccurrences(of: #"^\d+[\.\)]\s*|^step\s*\d+[:\.\-]?\s*"#, with: "", options: .regularExpression)
            }

        let fallbackSteps = lines.isEmpty ? ["Review uploaded procedure"] : Array(lines.prefix(4))
        let finalSteps = parsedSteps.isEmpty ? fallbackSteps : parsedSteps
        let materials = inferMaterials(from: lines)

        return Experiment(
            name: name.isEmpty ? "Custom Experiment" : name,
            subject: subject,
            difficulty: difficulty,
            time: method == "Paste text" ? "Custom" : "Imported",
            description: "Imported user procedure from \(method.lowercased()).",
            steps: finalSteps,
            materials: materials,
            isUploaded: true
        )
    }

    private func inferMaterials(from lines: [String]) -> [String] {
        let materialLine = lines.first { $0.lowercased().contains("material") || $0.lowercased().contains("equipment") }
        guard let materialLine else {
            return ["Lab setup", "Procedure notes"]
        }

        let split = materialLine
            .components(separatedBy: CharacterSet(charactersIn: ":,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(split.dropFirst().prefix(5)).isEmpty ? ["Lab setup", "Procedure notes"] : Array(split.dropFirst().prefix(5))
    }

    private func rebuildReport() {
        guard let experiment = currentExperiment else { return }

        let warnings = guidanceFeed.filter { $0.type == .warning }.map(\.message)
        let confirmations = guidanceFeed.filter { $0.type == .confirmed }.map(\.message)
        let qas = guidanceFeed.filter { $0.type == .qa }.map(\.message)

        generatedReport = LabReport(
            procedure: completedProcedure(from: experiment, confirmations: confirmations),
            observations: observationsText(confirmations: confirmations),
            errors: warnings,
            findings: [
                "Current step reached: \(min(currentStepIndex, experiment.steps.count)) of \(experiment.steps.count)",
                currentStatus == .error ? (lastErrorMessage ?? "Manual correction required before proceeding.") : "Procedure is progressing based on confirmed actions.",
                qas.last ?? "No spoken questions captured yet."
            ],
            suggestions: buildSuggestions(for: experiment, warnings: warnings)
        )
    }

    private func syncConnectionStatuses(camera: String = "Connected", audio: String) {
        connectionStatuses = [
            .init(label: "Camera", value: cameraStatusLabel(defaultValue: camera), color: IrisPalette.viridian),
            .init(label: "AI", value: appMode == .live ? (networkManager.isStreamConnected ? "Streaming" : "Waiting") : backendManager.connectionStatus, color: IrisPalette.flame),
            .init(label: "Audio", value: audioStatusLabel(defaultValue: audio), color: IrisPalette.coolAqua)
        ]
    }

    private func cameraStatusLabel(defaultValue: String) -> String {
        if isUsingExternalCamera {
            return "External"
        }
        switch cameraManager.authorizationStatus {
        case .authorized:
            return cameraManager.isSessionRunning ? "Connected" : defaultValue
        case .notDetermined:
            return "Pending"
        default:
            return "Denied"
        }
    }

    private func audioStatusLabel(defaultValue: String) -> String {
        if speechCoordinator.isListening {
            return "Listening"
        }
        if let error = speechCoordinator.errorMessage, !error.isEmpty {
            return "Error"
        }
        return defaultValue
    }

    private func localGuidance(for question: String, experiment: Experiment) -> String {
        let stepIndex = min(max(currentStepIndex - 1, 0), max(experiment.steps.count - 1, 0))
        let focusStep = experiment.steps[stepIndex]
        let materialSummary = experiment.materials.prefix(3).joined(separator: ", ")
        return "Focus on step \(currentStepIndex): \(focusStep). Use \(materialSummary.isEmpty ? "the listed materials" : materialSummary) to answer: \(question)"
    }

    private func completedProcedure(from experiment: Experiment, confirmations: [String]) -> [String] {
        guard !confirmations.isEmpty else { return [] }
        let completedCount = min(confirmations.count, experiment.steps.count)
        return Array(experiment.steps.prefix(completedCount))
    }

    private func observationsText(confirmations: [String]) -> String {
        if appMode == .live && !networkManager.currentGuidanceText.isEmpty {
            return networkManager.currentGuidanceText
        }
        if let lastConfirmation = confirmations.last {
            return lastConfirmation
        }
        if !backendManager.latestGuidance.isEmpty {
            return backendManager.latestGuidance
        }
        return "No observations captured yet."
    }

    private func buildSuggestions(for experiment: Experiment, warnings: [String]) -> [String] {
        var suggestions: [String] = []
        if !warnings.isEmpty {
            suggestions.append("Review the flagged issues before repeating the experiment.")
        }
        if !experiment.materials.isEmpty {
            suggestions.append("Prepare \(experiment.materials.prefix(3).joined(separator: ", ")) before restarting the procedure.")
        }
        if suggestions.isEmpty {
            suggestions.append("Complete at least one confirmed step or ask a question to generate report suggestions.")
        }
        return suggestions
    }

    private func saveExperiments() {
        guard let encoded = try? JSONEncoder().encode(experiments) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.experimentsStorageKey)
    }

    private static func loadExperiments() -> [Experiment] {
        guard
            let data = UserDefaults.standard.data(forKey: experimentsStorageKey),
            let decoded = try? JSONDecoder().decode([Experiment].self, from: data)
        else {
            return []
        }
        return decoded
    }
}

private struct BackendQuestionRequest: Codable {
    let experimentName: String
    let subject: String
    let currentStepIndex: Int
    let currentStep: String
    let question: String
    let materials: [String]
    let sessionId: String?
}

private struct BackendQuestionResponse: Codable {
    let answer: String?
    let response: String?
    let message: String?
    let text: String?
    let status: String?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case answer
        case response
        case message
        case text
        case status
        case sessionID = "sessionId"
    }
}

private struct BackendStartSessionRequest: Codable {
    let experimentName: String
    let subject: String
    let difficulty: String
    let time: String
    let description: String
    let steps: [String]
    let materials: [String]
    let cameraSource: String
}

private struct BackendStartSessionResponse: Codable {
    let sessionID: String
    let status: String
    let guidance: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case status
        case guidance
    }
}

private enum BackendEventType: String, Codable {
    case question
    case confirmed
    case warning
    case report
}

private struct BackendSessionEventRequest: Codable {
    let type: BackendEventType
    let message: String
}

private struct BackendStatusResponse: Codable {
    let status: String
}

private struct BackendCompleteSessionRequest: Codable {
    let procedure: [String]
    let observations: String
    let errors: [String]
    let findings: [String]
    let suggestions: [String]
}

private struct BackendCompleteSessionResponse: Codable {
    let status: String
    let summary: String
}
