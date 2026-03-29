//
//  AppServices.swift
//  IRIS
//

import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

@MainActor
final class CameraManager: NSObject, ObservableObject {
    private let sessionQueue = DispatchQueue(label: "iris.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputDelegate = CameraFrameOutputDelegate()
    private let imageContext = CIContext()
    private var lastFrameTimestamp = Date.distantPast

    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isSessionRunning = false
    @Published var errorMessage: String?
    @Published var selectedPosition: AVCaptureDevice.Position = .back

    nonisolated let session = AVCaptureSession()
    var onFrameCaptured: ((Data) -> Void)?

    override init() {
        super.init()
        videoOutputDelegate.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handleSampleBuffer(sampleBuffer)
        }
    }

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

                    if self.session.canAddOutput(self.videoOutput) {
                        if !self.session.outputs.contains(self.videoOutput) {
                            self.videoOutput.videoSettings = [
                                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                            ]
                            self.videoOutput.alwaysDiscardsLateVideoFrames = true
                            self.videoOutput.setSampleBufferDelegate(self.videoOutputDelegate, queue: self.sessionQueue)
                            self.session.addOutput(self.videoOutput)
                        }
                    }

                    if let connection = self.videoOutput.connection(with: .video),
                       connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
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

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard Date().timeIntervalSince(lastFrameTimestamp) >= 0.5 else { return }
        lastFrameTimestamp = Date()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)
        guard let jpegData = image.jpegData(compressionQuality: 0.6) else { return }

        Task { @MainActor [weak self] in
            self?.onFrameCaptured?(jpegData)
        }
    }
}

final class CameraFrameOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
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
    @Published var isAvailable = true

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
                stopAudioCapture()
                recognitionTask?.cancel()
                recognitionTask = nil
                recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                guard let recognitionRequest else { return }
                recognitionRequest.shouldReportPartialResults = true

                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.inputFormat(forBus: 0)
                guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                    isAvailable = false
                    throw NSError(
                        domain: "IRIS",
                        code: 406,
                        userInfo: [NSLocalizedDescriptionKey: "Microphone input is not available on this device."]
                    )
                }
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                    self?.recognitionRequest?.append(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()

                isAvailable = true
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
                isAvailable = false
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
        if audioEngine.isRunning {
            audioEngine.stop()
        }
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
    @Published var selectedCameraMode: CameraCaptureMode = .phone
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

    let speechCoordinator = SpeechCoordinator()
    let cameraManager = CameraManager()

    init() {
        experiments = Self.loadExperiments()
        cameraManager.onFrameCaptured = { [weak self] frameData in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCapturedPhoneFrame(frameData)
            }
        }
    }

    // ── Live session start — follows Sehreen's /start-experiment + WS flow ──
    func startLiveSession(for experiment: Experiment) async -> Bool {
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
        networkManager.resetSessionState()

        if appMode == .live {
            let backendSteps = await networkManager.startExperiment(
                type: experiment.backendType
            )
            if backendSteps.isEmpty {
                if let err = networkManager.errorMessage {
                    flagIssue(err)
                }
                isLive = false
                syncConnectionStatuses(audio: "Error")
                rebuildReport()
                return false
            }

            var liveExperiment = experiment
            liveExperiment.steps = backendSteps
            currentExperiment = liveExperiment
            guidanceFeed.append(GuidanceItem(
                type: .confirmed,
                message: "Loaded \(backendSteps.count) steps from Sehreen's backend."
            ))
            if isUsingExternalCamera {
                networkManager.connectStream()
                guidanceFeed.append(GuidanceItem(
                    type: .confirmed,
                    message: "Connected to glasses stream. Waiting for live guidance from Sehreen's backend."
                ))
                syncConnectionStatuses(audio: "Streaming")
            } else {
                networkManager.connectPhoneStream()
                guidanceFeed.append(GuidanceItem(
                    type: .confirmed,
                    message: "Using phone camera live stream. Frames are being sent directly to Sehreen's backend."
                ))
                syncConnectionStatuses(audio: "Ready")
            }
        } else {
            syncConnectionStatuses(audio: "Ready")
        }

        if isUsingExternalCamera {
            cameraManager.stopSession()
        } else {
            cameraManager.startSession(position: cameraManager.selectedPosition)
        }

        rebuildReport()
        return true
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
                    if self.isUsingExternalCamera {
                        self.networkManager.disconnectStream()
                    } else {
                        self.networkManager.disconnectPhoneStream()
                    }
                    self.networkManager.resetSessionState()
                    self.cameraManager.stopSession()
                    self.syncConnectionStatuses(camera: "Paused", audio: "Saved")
                    self.rebuildReport()
                }
            }
        } else {
            networkManager.resetSessionState()
            cameraManager.stopSession()
            syncConnectionStatuses(camera: "Paused", audio: "Saved")
            rebuildReport()
        }
    }

    func completeReportBuild() {
        reportStatus = .complete
        syncConnectionStatuses(audio: "Synced")
    }

    func prepareCamera(position: AVCaptureDevice.Position) {
        selectedCameraMode = .phone
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
        selectedCameraMode = .glasses
        isUsingExternalCamera = true
        cameraManager.stopSession()
        cameraSource = "Smart glasses · External stream"
        syncConnectionStatuses(camera: "External", audio: speechCoordinator.isListening ? "Listening" : "Ready")
    }

    func updateAppMode(_ mode: AppMode) {
        appMode = mode
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

    private func handleCapturedPhoneFrame(_ frameData: Data) async {
        guard appMode == .live, !isUsingExternalCamera else { return }
        guard let experiment = currentExperiment else { return }
        let safeIndex = min(max(currentStepIndex - 1, 0), max(experiment.steps.count - 1, 0))
        let currentStep = experiment.steps[safeIndex]
        await networkManager.sendPhoneFrame(
            frameData,
            experimentType: experiment.backendType,
            currentStep: currentStep
        )
    }

    private func syncConnectionStatuses(camera: String = "Connected", audio: String) {
        let aiStatus: String
        if appMode == .live {
            aiStatus = isUsingExternalCamera
                ? (networkManager.isStreamConnected ? "Streaming" : "Waiting")
                : "REST live"
        } else {
            aiStatus = "Demo"
        }

        connectionStatuses = [
            .init(label: "Camera", value: cameraStatusLabel(defaultValue: camera), color: IrisPalette.viridian),
            .init(label: "AI", value: aiStatus, color: IrisPalette.flame),
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
