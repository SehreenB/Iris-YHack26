//
//  AppServices.swift
//  IRIS
//

import AVFoundation
import AuthenticationServices
import Combine
import CoreImage
import CryptoKit
import Foundation
import PDFKit
import Security
import Speech
import SwiftUI
import UIKit

struct AuthenticatedUser: Codable, Hashable {
    let sub: String
    let name: String
    let email: String?
    let pictureURL: URL?
}

private struct Auth0Configuration {
    let domain: String
    let clientID: String
    let audience: String?
    let callbackScheme: String
    let redirectURI: String

    static func load() throws -> Auth0Configuration {
        let info = Bundle.main.infoDictionary ?? [:]
        let domain = (info["AUTH0_DOMAIN"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientID = (info["AUTH0_CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let audience = (info["AUTH0_AUDIENCE"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredScheme = (info["AUTH0_CALLBACK_SCHEME"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredRedirect = (info["AUTH0_REDIRECT_URI"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let callbackScheme = !configuredScheme.isEmpty ? configuredScheme : (Bundle.main.bundleIdentifier ?? "")
        let redirectURI: String

        if !configuredRedirect.isEmpty {
            redirectURI = configuredRedirect
        } else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? callbackScheme
            redirectURI = "\(callbackScheme)://\(domain)/ios/\(bundleIdentifier)/callback"
        }

        guard !domain.isEmpty else {
            throw Auth0ServiceError.misconfigured("Missing AUTH0_DOMAIN in Info.plist.")
        }
        guard !clientID.isEmpty else {
            throw Auth0ServiceError.misconfigured("Missing AUTH0_CLIENT_ID in Info.plist.")
        }
        guard !callbackScheme.isEmpty else {
            throw Auth0ServiceError.misconfigured("Missing AUTH0 callback scheme.")
        }

        return Auth0Configuration(
            domain: domain,
            clientID: clientID,
            audience: audience?.isEmpty == true ? nil : audience,
            callbackScheme: callbackScheme,
            redirectURI: redirectURI
        )
    }
}

private enum Auth0ServiceError: LocalizedError {
    case misconfigured(String)
    case invalidURL
    case authenticationCancelled
    case invalidCallback
    case invalidState
    case missingAuthorizationCode
    case tokenExchangeFailed(String)
    case userInfoFailed

    var errorDescription: String? {
        switch self {
        case let .misconfigured(message):
            return message
        case .invalidURL:
            return "Could not build the Auth0 request URL."
        case .authenticationCancelled:
            return "Sign in was cancelled."
        case .invalidCallback:
            return "Auth0 returned an invalid callback."
        case .invalidState:
            return "The Auth0 sign-in state did not match."
        case .missingAuthorizationCode:
            return "Auth0 did not return an authorization code."
        case let .tokenExchangeFailed(message):
            return message
        case .userInfoFailed:
            return "Could not load the authenticated user profile."
        }
    }
}

private struct PKCEPair {
    let verifier: String
    let challenge: String

    init() {
        let verifierData = Self.randomBytes(count: 32)
        verifier = Self.base64URLEncoded(verifierData)
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        challenge = Self.base64URLEncoded(challengeData)
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

private struct Auth0TokenResponse: Decodable {
    let accessToken: String
    let idToken: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case tokenType = "token_type"
    }
}

private struct Auth0UserInfoResponse: Decodable {
    let sub: String
    let name: String?
    let email: String?
    let picture: String?

    var user: AuthenticatedUser {
        AuthenticatedUser(
            sub: sub,
            name: name ?? email ?? "IRIS User",
            email: email,
            pictureURL: picture.flatMap(URL.init(string:))
        )
    }
}

private final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthenticationPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private final class Auth0Service {
    private var authSession: ASWebAuthenticationSession?

    func signInWithGoogle() async throws -> AuthenticatedUser {
        let configuration = try Auth0Configuration.load()
        let pkce = PKCEPair()
        let state = UUID().uuidString
        let callbackURL = try await authenticate(configuration: configuration, pkce: pkce, state: state)
        let code = try authorizationCode(from: callbackURL, expectedState: state)
        let tokenResponse = try await exchangeCode(
            code,
            pkceVerifier: pkce.verifier,
            configuration: configuration
        )
        return try await fetchUserProfile(
            accessToken: tokenResponse.accessToken,
            configuration: configuration
        )
    }

    private func authenticate(configuration: Auth0Configuration, pkce: PKCEPair, state: String) async throws -> URL {
        guard var components = URLComponents(string: "https://\(configuration.domain)/authorize") else {
            throw Auth0ServiceError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "connection", value: "google-oauth2"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        if let audience = configuration.audience {
            queryItems.append(URLQueryItem(name: "audience", value: audience))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw Auth0ServiceError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil

                if let nsError = error as NSError? {
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: Auth0ServiceError.authenticationCancelled)
                    } else {
                        continuation.resume(throwing: nsError)
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: Auth0ServiceError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = WebAuthenticationPresentationContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw Auth0ServiceError.invalidCallback
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error_description" })?.value ??
            queryItems.first(where: { $0.name == "error" })?.value {
            throw Auth0ServiceError.tokenExchangeFailed(error)
        }

        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        guard returnedState == expectedState else {
            throw Auth0ServiceError.invalidState
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw Auth0ServiceError.missingAuthorizationCode
        }

        return code
    }

    private func exchangeCode(
        _ code: String,
        pkceVerifier: String,
        configuration: Auth0Configuration
    ) async throws -> Auth0TokenResponse {
        guard let url = URL(string: "https://\(configuration.domain)/oauth/token") else {
            throw Auth0ServiceError.invalidURL
        }

        struct TokenRequest: Encodable {
            let grantType = "authorization_code"
            let clientID: String
            let code: String
            let codeVerifier: String
            let redirectURI: String

            enum CodingKeys: String, CodingKey {
                case grantType = "grant_type"
                case clientID = "client_id"
                case code
                case codeVerifier = "code_verifier"
                case redirectURI = "redirect_uri"
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TokenRequest(
                clientID: configuration.clientID,
                code: code,
                codeVerifier: pkceVerifier,
                redirectURI: configuration.redirectURI
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Auth0 token exchange failed."
            throw Auth0ServiceError.tokenExchangeFailed(message)
        }

        return try JSONDecoder().decode(Auth0TokenResponse.self, from: data)
    }

    private func fetchUserProfile(accessToken: String, configuration: Auth0Configuration) async throws -> AuthenticatedUser {
        guard let url = URL(string: "https://\(configuration.domain)/userinfo") else {
            throw Auth0ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw Auth0ServiceError.userInfoFailed
        }

        let profile = try JSONDecoder().decode(Auth0UserInfoResponse.self, from: data)
        return profile.user
    }
}

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

struct ProcedureNormalizationResult {
    let cleanedText: String
    let parsedSteps: [String]
    let materials: [String]
    let suggestedName: String?
}

struct LocalImportNormalizationService {
    func normalize(rawText: String) -> ProcedureNormalizationResult {
        let lines = cleanedLines(from: rawText)
        let parsedSteps = extractSteps(from: lines)
        let materials = inferMaterials(from: lines)
        let suggestedName = inferName(from: lines)

        return ProcedureNormalizationResult(
            cleanedText: lines.joined(separator: "\n"),
            parsedSteps: parsedSteps.isEmpty ? fallbackSteps(from: lines) : parsedSteps,
            materials: materials,
            suggestedName: suggestedName
        )
    }

    func normalizeURL(from rawValue: String) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(rawValue)")
    }

    func extractProcedureText(fromPDFData data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        let extractedText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !extractedText.isEmpty else { return nil }
        return normalize(rawText: extractedText).cleanedText
    }

    func extractReadableText(fromHTML html: String) -> String {
        let strippedScripts = html.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: " ",
            options: .regularExpression
        )
        let strippedStyles = strippedScripts.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: " ",
            options: .regularExpression
        )
        let withoutTags = strippedStyles.replacingOccurrences(
            of: "<[^>]+>",
            with: "\n",
            options: .regularExpression
        )
        return normalize(rawText: withoutTags).cleanedText
    }

    private func cleanedLines(from rawText: String) -> [String] {
        rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty &&
                line.count > 2 &&
                !line.hasPrefix("http") &&
                !line.lowercased().contains("cookie")
            }
    }

    private func extractSteps(from lines: [String]) -> [String] {
        lines
            .filter { line in
                guard let firstCharacter = line.first else { return false }
                return firstCharacter.isNumber || line.lowercased().hasPrefix("step")
            }
            .map {
                $0.replacingOccurrences(
                    of: #"^\d+[\.\)]\s*|^step\s*\d+[:\.\-]?\s*"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { !$0.isEmpty }
    }

    private func fallbackSteps(from lines: [String]) -> [String] {
        guard !lines.isEmpty else { return ["Review uploaded procedure"] }
        return Array(lines.prefix(4))
    }

    private func inferMaterials(from lines: [String]) -> [String] {
        let materialLine = lines.first {
            $0.lowercased().contains("material") || $0.lowercased().contains("equipment")
        }

        guard let materialLine else {
            return ["Lab setup", "Procedure notes"]
        }

        let split = materialLine
            .components(separatedBy: CharacterSet(charactersIn: ":,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let extracted = Array(split.dropFirst().prefix(6))
        return extracted.isEmpty ? ["Lab setup", "Procedure notes"] : extracted
    }

    private func inferName(from lines: [String]) -> String? {
        lines.first { line in
            let lowered = line.lowercased()
            let startsWithNumber = line.first?.isNumber ?? false
            return !lowered.hasPrefix("step") &&
            !lowered.contains("material") &&
            !lowered.contains("equipment") &&
            !startsWithNumber &&
            line.count <= 80
        }
    }
}

struct PhoneVisionFeedback {
    let message: String
    let isWarning: Bool
}

@MainActor
final class LocalGuidanceSpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var lastSpokenText = ""
    private var lastLanguage: AppLanguage = .english

    private var elevenLabsAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var elevenLabsVoiceID: String {
        (Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_VOICE_ID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func speak(_ text: String, language: AppLanguage = .english) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText != lastSpokenText else { return }
        lastSpokenText = trimmedText
        lastLanguage = language

        if !elevenLabsAPIKey.isEmpty, !elevenLabsVoiceID.isEmpty, let audioData = await requestElevenLabsAudio(for: trimmedText) {
            play(audioData)
            return
        }

        speakWithSystemVoice(trimmedText, language: language)
    }

    private func requestElevenLabsAudio(for text: String) async -> Data? {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(elevenLabsVoiceID)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")

        let payload: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "output_format": "mp3_44100_128"
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func play(_ data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            speakWithSystemVoice(lastSpokenText, language: lastLanguage)
        }
    }

    private func speakWithSystemVoice(_ text: String, language: AppLanguage) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.96
        synthesizer.speak(utterance)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
}

final class PhoneVisionFallbackService {
    private let context = CIContext()

    func analyze(frameData: Data, currentStep: String, materials: [String]) -> PhoneVisionFeedback? {
        guard let image = CIImage(data: frameData) else { return nil }

        let extent = image.extent
        guard !extent.isEmpty else { return nil }

        let brightness = averageBrightness(for: image, extent: extent)
        let edgeStrength = averageEdgeStrength(for: image, extent: extent)
        let focusMaterial = materials.first?.lowercased() ?? "equipment"

        if brightness < 0.18 {
            return PhoneVisionFeedback(
                message: "Phone vision fallback: the scene is too dark. Add more light before \(currentStep.lowercased()).",
                isWarning: true
            )
        }

        if brightness > 0.92 {
            return PhoneVisionFeedback(
                message: "Phone vision fallback: there is too much glare. Tilt the phone slightly so the \(focusMaterial) stays visible.",
                isWarning: true
            )
        }

        if edgeStrength < 0.045 {
            return PhoneVisionFeedback(
                message: "Phone vision fallback: move a little closer and hold steady so IRIS can clearly see the \(focusMaterial).",
                isWarning: true
            )
        }

        return PhoneVisionFeedback(
            message: "Phone vision fallback: the camera view is clear. Keep the \(focusMaterial) framed while you \(currentStep.lowercased()).",
            isWarning: false
        )
    }

    private func averageBrightness(for image: CIImage, extent: CGRect) -> CGFloat {
        guard
            let filter = CIFilter(name: "CIAreaAverage"),
            let output = areaAverageOutput(for: image, extent: extent, using: filter)
        else {
            return 0.5
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let red = CGFloat(bitmap[0]) / 255
        let green = CGFloat(bitmap[1]) / 255
        let blue = CGFloat(bitmap[2]) / 255
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private func averageEdgeStrength(for image: CIImage, extent: CGRect) -> CGFloat {
        guard
            let edges = CIFilter(name: "CIEdges"),
            let edgeImage = edgeOutput(for: image, using: edges),
            let areaAverage = CIFilter(name: "CIAreaAverage"),
            let output = areaAverageOutput(for: edgeImage, extent: edgeImage.extent, using: areaAverage)
        else {
            return 0.1
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return CGFloat(bitmap[0]) / 255
    }

    private func areaAverageOutput(for image: CIImage, extent: CGRect, using filter: CIFilter) -> CIImage? {
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        return filter.outputImage
    }

    private func edgeOutput(for image: CIImage, using filter: CIFilter) -> CIImage? {
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(6.0, forKey: kCIInputIntensityKey)
        return filter.outputImage
    }
}

@MainActor
final class SpeechCoordinator: ObservableObject {
    private enum ListeningMode {
        case manual
        case wakeWord
    }

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var listeningMode: ListeningMode?
    private var hasTriggeredWakePhrase = false

    @Published var isListening = false
    @Published var isWakeListening = false
    @Published var liveTranscript = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var microphoneGranted = false
    @Published var errorMessage: String?
    @Published var isAvailable = true

    var onWakePhraseDetected: ((String?) -> Void)?

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
        startRecognition(mode: .manual)
    }

    func startWakeListening() {
        guard !isWakeListening else { return }
        startRecognition(mode: .wakeWord)
    }

    func stopWakeListening() {
        guard listeningMode == .wakeWord else { return }
        stopAudioCapture()
    }

    private func startRecognition(mode: ListeningMode) {
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
                hasTriggeredWakePhrase = false
                listeningMode = mode

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
                if mode == .manual {
                    liveTranscript = ""
                    isListening = true
                    isWakeListening = false
                } else {
                    isListening = false
                    isWakeListening = true
                }
                errorMessage = nil

                recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let result {
                            switch mode {
                            case .manual:
                                self.liveTranscript = result.bestTranscription.formattedString
                            case .wakeWord:
                                self.handleWakeTranscript(result.bestTranscription.formattedString)
                            }
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

    private func handleWakeTranscript(_ transcript: String) {
        let loweredTranscript = transcript.lowercased()
        guard !hasTriggeredWakePhrase, let range = loweredTranscript.range(of: "hey iris") else { return }

        hasTriggeredWakePhrase = true
        let trailing = transcript[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudioCapture()
        onWakePhraseDetected?(trailing.isEmpty ? nil : trailing)
    }

    private func stopAudioCapture() {
        isListening = false
        isWakeListening = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        listeningMode = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class AppSession: ObservableObject {
    private static let experimentsStorageKey = "iris.saved.experiments"
    private static let appearanceStorageKey = "iris.settings.appearance"
    private static let languageStorageKey = "iris.settings.language"
    private static let authenticatedUserStorageKey = "iris.auth.user"
    private let importNormalizationService = LocalImportNormalizationService()
    private let phoneVisionFallbackService = PhoneVisionFallbackService()
    private let localGuidanceSpeechService = LocalGuidanceSpeechService()
    private let authService = Auth0Service()
    private var searchTask: Task<Void, Never>?
    private var wakeFollowUpTask: Task<Void, Never>?
    private var lastPhoneFallbackMessage = ""
    private var lastPhoneFallbackTimestamp = Date.distantPast
    private var lastPhoneAnalysisTimestamp = Date.distantPast
    private var isAwaitingVoiceFollowUp = false

    @Published var activeScreen: Screen = .landing
    @Published var currentExperiment: Experiment?
    @Published var experiments: [Experiment]
    @Published var showUploadSheet = false
    @Published var isLive = false
    @Published var isSessionPaused = false
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
    @Published var remoteSearchResults: [Experiment] = []
    @Published var remoteSearchQuery = ""
    @Published var appearanceMode: AppearanceMode
    @Published var selectedLanguage: AppLanguage
    @Published var authenticatedUser: AuthenticatedUser?
    @Published var isAuthenticating = false
    @Published var authErrorMessage: String?

    // ── NetworkManager — Sehreen's backend ────────────────────────────────────
    let networkManager = NetworkManager()

    let speechCoordinator = SpeechCoordinator()
    let cameraManager = CameraManager()

    private var usesRemoteBackend: Bool {
        appMode == .live && isUsingExternalCamera
    }

    private var isVoiceInteractionInProgress: Bool {
        speechCoordinator.isListening || isAwaitingVoiceFollowUp
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }

    var appLocale: Locale {
        Locale(identifier: selectedLanguage.localeIdentifier)
    }

    func t(_ text: String) -> String {
        selectedLanguage.localized(text)
    }

    private func localizedExperimentName(_ experiment: Experiment) -> String {
        experiment.localizedName(selectedLanguage)
    }

    private func localizedStepList(_ experiment: Experiment) -> [String] {
        experiment.localizedSteps(selectedLanguage)
    }

    private func localizedMaterials(_ experiment: Experiment) -> [String] {
        experiment.localizedMaterials(selectedLanguage)
    }

    init() {
        experiments = Self.loadExperiments()
        appearanceMode = Self.loadAppearanceMode()
        selectedLanguage = Self.loadLanguage()
        authenticatedUser = Self.loadAuthenticatedUser()
        if authenticatedUser != nil {
            activeScreen = .home
        }
        cameraManager.onFrameCaptured = { [weak self] frameData in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCapturedPhoneFrame(frameData)
            }
        }
        speechCoordinator.onWakePhraseDetected = { [weak self] trailingQuestion in
            guard let self else { return }
            Task { @MainActor in
                await self.handleWakePhrase(trailingQuestion)
            }
        }
    }

    var isAuthenticated: Bool {
        authenticatedUser != nil
    }

    @discardableResult
    func signInWithGoogle() async -> Bool {
        authErrorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let user = try await authService.signInWithGoogle()
            authenticatedUser = user
            saveAuthenticatedUser(user)
            return true
        } catch {
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() {
        authenticatedUser = nil
        authErrorMessage = nil
        currentExperiment = nil
        isLive = false
        isSessionPaused = false
        showUploadSheet = false
        activeScreen = .landing
        UserDefaults.standard.removeObject(forKey: Self.authenticatedUserStorageKey)
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
        isSessionPaused = false
        reportStatus = .building
        guidanceFeed = []
        networkManager.resetSessionState()

        if usesRemoteBackend {
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
            networkManager.connectStream()
            guidanceFeed.append(GuidanceItem(
                type: .confirmed,
                message: t("Connected to glasses stream. Waiting for live guidance from Sehreen's backend.")
            ))
            syncConnectionStatuses(audio: "Streaming")
        } else {
            if !isUsingExternalCamera {
                guidanceFeed.append(GuidanceItem(
                    type: .confirmed,
                    message: t("Phone camera mode runs locally on-device without Sehreen's backend.")
                ))
            }
            syncConnectionStatuses(audio: "Ready")
        }

        if isUsingExternalCamera {
            cameraManager.stopSession()
        } else {
            cameraManager.startSession(position: cameraManager.selectedPosition)
        }

        rebuildReport()
        startWakePhraseMonitoring()
        return true
    }

    func acknowledgeError() {
        currentStatus = .watching
        lastErrorMessage = nil
        rebuildReport()
    }

    func beginListening() {
        guard isLive, !isSessionPaused else { return }
        isAwaitingVoiceFollowUp = true
        speechCoordinator.stopWakeListening()
        speechCoordinator.startListening()
        syncConnectionStatuses(audio: "Listening")
    }

    @discardableResult
    func completeListeningTurn() -> String {
        let finalTranscript = speechCoordinator.stopListening()
        isAwaitingVoiceFollowUp = false
        if !finalTranscript.isEmpty {
            transcript = finalTranscript
        }
        syncConnectionStatuses(audio: "Ready")
        restartWakePhraseMonitoringIfNeeded()
        return finalTranscript
    }

    func submitQuestion(_ question: String) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }

        transcript = trimmedQuestion
        guidanceFeed.append(GuidanceItem(type: .qa, message: "Q: \(transcript)"))

        if !usesRemoteBackend {
            guard let experiment = currentExperiment else { return }
            let localizedSteps = localizedStepList(experiment)
            let stepIndex = min(max(currentStepIndex - 1, 0), max(localizedSteps.count - 1, 0))
            let focusStep = localizedSteps[stepIndex]
            Task {
                let response = await networkManager.answerPhoneQuestion(
                    trimmedQuestion,
                    experimentName: localizedExperimentName(experiment),
                    currentStep: focusStep,
                    materials: localizedMaterials(experiment),
                    language: selectedLanguage
                ) ?? localGuidance(for: trimmedQuestion, experiment: experiment)

                await MainActor.run {
                    self.guidanceFeed.append(GuidanceItem(type: .qa, message: response))
                    self.syncConnectionStatuses(audio: "Ready")
                    self.rebuildReport()
                }

                await self.localGuidanceSpeechService.speak(response, language: self.selectedLanguage)
            }
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

        let completedStep = localizedStepList(experiment)[currentStepIndex - 1]
        localGuidanceSpeechService.stop()
        networkManager.stopAudioPlayback()
        guidanceFeed.append(GuidanceItem(type: .confirmed, message: "Completed step \(currentStepIndex): \(completedStep)"))

        if usesRemoteBackend {
            networkManager.advanceStep()
        }

        if currentStepIndex < experiment.steps.count {
            currentStepIndex += 1
            currentStatus = .watching
            lastErrorMessage = nil
            let nextStepMessage = localizedStepPrompt(for: experiment, stepIndex: currentStepIndex - 1)
            networkManager.currentGuidanceText = nextStepMessage
            guidanceFeed.append(GuidanceItem(type: .confirmed, message: nextStepMessage))
            Task {
                await self.localGuidanceSpeechService.speak(nextStepMessage, language: self.selectedLanguage)
            }
        } else {
            networkManager.currentGuidanceText = ""
            guidanceFeed.append(GuidanceItem(type: .confirmed, message: t("Experiment flow completed. Review the report for final notes.")))
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
        isSessionPaused = false
        wakeFollowUpTask?.cancel()
        speechCoordinator.stopWakeListening()
        _ = speechCoordinator.stopListening()
        localGuidanceSpeechService.stop()
        networkManager.stopAudioPlayback()
        reportStatus = .complete
        if usesRemoteBackend {
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
            let completedSteps = generatedReport.procedure
            let warnings = generatedReport.errors
            let experimentName = currentExperiment.map(localizedExperimentName) ?? t("Lab session")
            Task {
                let summary = await networkManager.summarizePhoneExperiment(
                    experimentName: experimentName,
                    completedSteps: completedSteps,
                    warnings: warnings,
                    language: selectedLanguage
                ) ?? self.generatedReport.findings.last ?? "Experiment session completed."

                await MainActor.run {
                    self.guidanceFeed.append(GuidanceItem(type: .confirmed, message: summary))
                    self.generatedReport.observations = summary
                    self.rebuildReport()
                }
                await self.localGuidanceSpeechService.speak(summary, language: self.selectedLanguage)
            }
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
        isUsingExternalCamera = false
        cameraManager.startSession(position: .back)
        updateCameraSource(position: .back)
        cameraSource = "Smart glasses · On-device analysis"
        syncConnectionStatuses(camera: "Glasses", audio: speechCoordinator.isListening ? "Listening" : "Ready")
    }

    func updateAppMode(_ mode: AppMode) {
        appMode = mode
        syncConnectionStatuses(audio: speechCoordinator.isListening ? "Listening" : "Ready")
    }

    func pauseActiveSession() {
        guard isLive, !isSessionPaused else { return }
        isSessionPaused = true
        wakeFollowUpTask?.cancel()
        isAwaitingVoiceFollowUp = false
        _ = speechCoordinator.stopListening()
        speechCoordinator.stopWakeListening()
        localGuidanceSpeechService.stop()
        networkManager.stopAudioPlayback()

        if usesRemoteBackend {
            networkManager.disconnectStream()
        }
        cameraManager.stopSession()
        syncConnectionStatuses(camera: "Paused", audio: "Paused")
        guidanceFeed.append(GuidanceItem(type: .confirmed, message: t("Lab paused. Return and tap Continue lab when you're ready.")))
        rebuildReport()
    }

    func resumePausedSession() {
        guard isLive, isSessionPaused else { return }
        isSessionPaused = false

        if usesRemoteBackend {
            networkManager.connectStream()
            syncConnectionStatuses(camera: "External", audio: "Streaming")
        } else {
            cameraManager.startSession(position: cameraManager.selectedPosition)
            syncConnectionStatuses(audio: "Ready")
        }

        guidanceFeed.append(GuidanceItem(type: .confirmed, message: t("Lab resumed. IRIS is watching the current step again.")))
        rebuildReport()
        startWakePhraseMonitoring()
    }

    func updateAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceStorageKey)
    }

    func updateLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.languageStorageKey)
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

    func normalizedProcedureText(from rawText: String) -> String {
        importNormalizationService.normalize(rawText: rawText).cleanedText
    }

    func extractProcedureText(fromPDFData data: Data) -> String? {
        importNormalizationService.extractProcedureText(fromPDFData: data)
    }

    func extractProcedureText(fromHTML html: String) -> String {
        importNormalizationService.extractReadableText(fromHTML: html)
    }

    func normalizedImportURL(from rawValue: String) -> URL? {
        importNormalizationService.normalizeURL(from: rawValue)
    }

    func suggestedExperimentName(from rawText: String, fallback: String? = nil) -> String? {
        let normalized = importNormalizationService.normalize(rawText: rawText)
        return normalized.suggestedName ?? fallback
    }

    func updateSearchQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteSearchQuery = trimmedQuery
        searchTask?.cancel()

        guard trimmedQuery.count >= 2 else {
            remoteSearchResults = []
            networkManager.searchErrorMessage = nil
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let results = await self.networkManager.searchExperiments(query: trimmedQuery, language: self.selectedLanguage)
            guard !Task.isCancelled, self.remoteSearchQuery == trimmedQuery else { return }
            self.remoteSearchResults = results
        }
    }

    private func parseExperiment(
        from rawText: String,
        name: String,
        subject: Subject,
        difficulty: Difficulty,
        method: String
    ) -> Experiment {
        let normalizedProcedure = importNormalizationService.normalize(rawText: rawText)
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionSource = method == "Paste text" ? "pasted procedure" : method.lowercased()

        return Experiment(
            name: resolvedName.isEmpty ? (normalizedProcedure.suggestedName ?? "Custom Experiment") : resolvedName,
            subject: subject,
            difficulty: difficulty,
            time: method == "Paste text" ? "Custom" : "Imported",
            description: "Imported user procedure from \(descriptionSource).",
            steps: normalizedProcedure.parsedSteps,
            materials: normalizedProcedure.materials,
            isUploaded: true
        )
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
        guard isLive, !isSessionPaused, !isUsingExternalCamera else { return }
        guard !isVoiceInteractionInProgress else { return }
        guard let experiment = currentExperiment else { return }
        guard Date().timeIntervalSince(lastPhoneAnalysisTimestamp) >= 3 else { return }
        lastPhoneAnalysisTimestamp = Date()
        let localizedSteps = localizedStepList(experiment)
        let safeIndex = min(max(currentStepIndex - 1, 0), max(localizedSteps.count - 1, 0))
        let currentStep = localizedSteps[safeIndex]
        if usesRemoteBackend && networkManager.isStreamConnected {
            await networkManager.sendPhoneFrame(
                frameData,
                experimentType: experiment.backendType,
                currentStep: currentStep
            )
            return
        }

        if let analysis = await networkManager.analyzePhoneFrame(
            frameData,
            experimentName: localizedExperimentName(experiment),
            experimentType: experiment.backendType,
            currentStep: currentStep,
            materials: localizedMaterials(experiment),
            language: selectedLanguage
        ) {
            await publishPhoneFeedback(
                message: analysis.message,
                isWarning: analysis.isWarning,
                shouldStore: analysis.shouldStore,
                shouldAdvance: analysis.shouldAdvance
            )
            return
        }

        guard let fallback = phoneVisionFallbackService.analyze(
            frameData: frameData,
            currentStep: currentStep,
            materials: localizedMaterials(experiment)
        ) else { return }

        await publishPhoneFeedback(
            message: fallback.message,
            isWarning: fallback.isWarning,
            shouldStore: true,
            shouldAdvance: false
        )
    }

    private func publishPhoneFeedback(message: String, isWarning: Bool, shouldStore: Bool, shouldAdvance: Bool) async {
        guard shouldPublishPhoneFallback(message) else { return }
        networkManager.currentGuidanceText = message
        await localGuidanceSpeechService.speak(message, language: selectedLanguage)

        guard shouldStore else { return }

        if isWarning {
            flagIssue(message)
            syncConnectionStatuses(audio: "Phone vision")
        } else if shouldAdvance {
            autoAdvanceCurrentStep(from: message)
        } else {
            guidanceFeed.append(GuidanceItem(type: .confirmed, message: message))
            currentStatus = .watching
            lastErrorMessage = nil
            syncConnectionStatuses(audio: "Phone vision")
            rebuildReport()
        }
    }

    private func autoAdvanceCurrentStep(from message: String) {
        guard let experiment = currentExperiment, currentStepIndex <= experiment.steps.count else { return }

        localGuidanceSpeechService.stop()
        networkManager.stopAudioPlayback()
        let completedStep = localizedStepList(experiment)[currentStepIndex - 1]
        guidanceFeed.append(GuidanceItem(type: .confirmed, message: "Completed step \(currentStepIndex): \(completedStep)"))
        guidanceFeed.append(GuidanceItem(type: .confirmed, message: message))

        currentStatus = .watching
        lastErrorMessage = nil

        if currentStepIndex < experiment.steps.count {
            currentStepIndex += 1
            let nextStepMessage = localizedStepPrompt(for: experiment, stepIndex: currentStepIndex - 1)
            networkManager.currentGuidanceText = nextStepMessage
            guidanceFeed.append(GuidanceItem(type: .confirmed, message: nextStepMessage))
            Task {
                await self.localGuidanceSpeechService.speak(nextStepMessage, language: self.selectedLanguage)
            }
        } else {
            networkManager.currentGuidanceText = ""
            guidanceFeed.append(GuidanceItem(type: .confirmed, message: t("Experiment flow completed. Review the report for final notes.")))
        }

        syncConnectionStatuses(audio: "Phone vision")
        rebuildReport()
    }

    private func localizedStepPrompt(for experiment: Experiment, stepIndex: Int) -> String {
        let localizedSteps = localizedStepList(experiment)
        guard localizedSteps.indices.contains(stepIndex) else {
            return t("Experiment flow completed. Review the report for final notes.")
        }
        return "\(t("Current step")) \(stepIndex + 1): \(localizedSteps[stepIndex])"
    }

    private func syncConnectionStatuses(camera: String = "Connected", audio: String) {
        let aiStatus: String
        if usesRemoteBackend {
            aiStatus = isUsingExternalCamera
                ? (networkManager.isStreamConnected ? "Streaming" : "Waiting")
                : (networkManager.isStreamConnected ? "Phone live" : "Phone local")
        } else if isLive, !isUsingExternalCamera {
            aiStatus = "On-device"
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
        if speechCoordinator.isWakeListening {
            return "Wake word"
        }
        if let error = speechCoordinator.errorMessage, !error.isEmpty {
            return "Error"
        }
        return defaultValue
    }

    private func localGuidance(for question: String, experiment: Experiment) -> String {
        let localizedSteps = localizedStepList(experiment)
        let stepIndex = min(max(currentStepIndex - 1, 0), max(localizedSteps.count - 1, 0))
        let focusStep = localizedSteps[stepIndex]
        let materialSummary = localizedMaterials(experiment).prefix(3).joined(separator: ", ")
        return "Focus on step \(currentStepIndex): \(focusStep). Use \(materialSummary.isEmpty ? "the listed materials" : materialSummary) to answer: \(question)"
    }

    private func shouldPublishPhoneFallback(_ message: String) -> Bool {
        let now = Date()
        guard message != lastPhoneFallbackMessage || now.timeIntervalSince(lastPhoneFallbackTimestamp) > 4 else {
            return false
        }
        lastPhoneFallbackMessage = message
        lastPhoneFallbackTimestamp = now
        return true
    }

    private func startWakePhraseMonitoring() {
        guard isLive, !isSessionPaused else { return }
        guard !speechCoordinator.isListening else { return }
        guard !isAwaitingVoiceFollowUp else { return }
        speechCoordinator.startWakeListening()
        syncConnectionStatuses(audio: "Wake word")
    }

    private func restartWakePhraseMonitoringIfNeeded() {
        guard isLive, !isSessionPaused else { return }
        wakeFollowUpTask?.cancel()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard self.isLive, !self.isSessionPaused, !self.speechCoordinator.isListening else { return }
            self.startWakePhraseMonitoring()
        }
    }

    private func handleWakePhrase(_ trailingQuestion: String?) async {
        guard isLive, !isSessionPaused else { return }
        wakeFollowUpTask?.cancel()
        isAwaitingVoiceFollowUp = true
        let acknowledgement = t("I'm here. Ask me about this step.")

        if let trailingQuestion, !trailingQuestion.isEmpty {
            transcript = trailingQuestion
            submitQuestion(trailingQuestion)
            isAwaitingVoiceFollowUp = false
            restartWakePhraseMonitoringIfNeeded()
            return
        }

        guidanceFeed.append(GuidanceItem(type: .qa, message: acknowledgement))
        rebuildReport()
        await localGuidanceSpeechService.speak(acknowledgement, language: selectedLanguage)

        wakeFollowUpTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard self.isLive else { return }
            self.speechCoordinator.startListening()
            self.syncConnectionStatuses(audio: "Listening")

            try? await Task.sleep(for: .seconds(5))
            guard self.speechCoordinator.isListening else {
                self.isAwaitingVoiceFollowUp = false
                self.restartWakePhraseMonitoringIfNeeded()
                return
            }

            let followUp = self.completeListeningTurn()
            if !followUp.isEmpty {
                self.submitQuestion(followUp)
            } else {
                self.restartWakePhraseMonitoringIfNeeded()
            }
        }
    }

    private func completedProcedure(from experiment: Experiment, confirmations: [String]) -> [String] {
        guard !confirmations.isEmpty else { return [] }
        let completedCount = min(confirmations.count, experiment.steps.count)
        return Array(experiment.steps.prefix(completedCount))
    }

    private func observationsText(confirmations: [String]) -> String {
        if (usesRemoteBackend || (!isUsingExternalCamera && isLive)) && !networkManager.currentGuidanceText.isEmpty {
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
        let savedExperiments: [Experiment]
        if
            let data = UserDefaults.standard.data(forKey: experimentsStorageKey),
            let decoded = try? JSONDecoder().decode([Experiment].self, from: data)
        {
            savedExperiments = decoded
        } else {
            savedExperiments = []
        }

        var deduplicatedExperiments: [Experiment] = []

        for experiment in savedExperiments + Experiment.demoExperiments {
            if let existingIndex = deduplicatedExperiments.firstIndex(where: {
                $0.name.caseInsensitiveCompare(experiment.name) == .orderedSame
            }) {
                let existingExperiment = deduplicatedExperiments[existingIndex]
                if experiment.createdAt >= existingExperiment.createdAt {
                    deduplicatedExperiments[existingIndex] = experiment
                }
            } else {
                deduplicatedExperiments.append(experiment)
            }
        }

        return deduplicatedExperiments.sorted { $0.createdAt > $1.createdAt }
    }

    private static func loadAppearanceMode() -> AppearanceMode {
        guard
            let rawValue = UserDefaults.standard.string(forKey: appearanceStorageKey),
            let mode = AppearanceMode(rawValue: rawValue)
        else {
            return .light
        }
        return mode
    }

    private static func loadLanguage() -> AppLanguage {
        guard
            let rawValue = UserDefaults.standard.string(forKey: languageStorageKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .english
        }
        return language
    }

    private static func loadAuthenticatedUser() -> AuthenticatedUser? {
        guard let data = UserDefaults.standard.data(forKey: authenticatedUserStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthenticatedUser.self, from: data)
    }

    private func saveAuthenticatedUser(_ user: AuthenticatedUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: Self.authenticatedUserStorageKey)
    }
}
