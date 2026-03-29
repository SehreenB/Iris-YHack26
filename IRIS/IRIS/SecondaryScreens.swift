//
//  SecondaryScreens.swift
//  IRIS
//
//  Changes from original:
//  - AssistantScreen: added live guidance banner from networkManager.currentGuidanceText
//  - AssistantScreen: shows networkManager.errorMessage in red if stream fails
//  - Everything else is identical to original
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct AssistantScreen: View {
    let experiment: Experiment
    @ObservedObject var session: AppSession
    let onEnd: () -> Void

    @GestureState private var isPressing = false
    @State private var questionDraft = ""
    @State private var issueDraft = ""

    private var activeExperiment: Experiment {
        session.currentExperiment ?? experiment
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        NavBar(
                            title: experiment.localizedName(session.selectedLanguage),
                            label: session.t("LIVE SESSION"),
                            foreground: .white,
                            compact: true,
                            rightElement: AnyView(
                                HStack(spacing: 10) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 6, height: 6)
                                        Text(session.t("Live"))
                                            .font(.irisEyebrow)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(IrisPalette.flame, in: Capsule())

                                    Button(action: onEnd) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 30, height: 30)
                                            .background(Color.white.opacity(0.12), in: Circle())
                                    }
                                }
                            )
                        )
                    }
                    .padding(.bottom, 8)
                    .background(IrisPalette.tealInk)

                    ZStack {
                        if session.selectedCameraMode == .glasses {
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(IrisPalette.tealInk)
                                .frame(height: 240)

                        VStack(spacing: 10) {
                            Circle()
                                .fill(IrisPalette.viridian.opacity(0.15))
                                .frame(width: 54, height: 54)
                                .overlay {
                                        Image(systemName: "eyeglasses")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundStyle(IrisPalette.viridian)
                                }

                            Text(session.cameraSource)
                                .font(.irisBodySmall)
                                .foregroundStyle(IrisPalette.viridian)
                        }
                    } else {
                        CameraPreviewView(session: session.cameraManager.session)
                            .frame(height: 240)

                        if session.cameraManager.authorizationStatus != .authorized || !session.cameraManager.isSessionRunning {
                            Rectangle()
                                .fill(IrisPalette.tealInk.opacity(0.86))
                                .frame(height: 240)

                            VStack(spacing: 10) {
                                Circle()
                                    .fill(IrisPalette.viridian.opacity(0.15))
                                    .frame(width: 54, height: 54)
                                    .overlay {
                                        Image(systemName: session.cameraManager.authorizationStatus == .denied ? "camera.slash.fill" : "camera.fill")
                                            .font(.system(size: 24, weight: .medium))
                                            .foregroundStyle(IrisPalette.viridian)
                                    }

                                Text(session.cameraSource)
                                    .font(.irisBodySmall)
                                    .foregroundStyle(IrisPalette.viridian)

                                if let errorMessage = session.cameraManager.errorMessage, !errorMessage.isEmpty {
                                    Text(errorMessage)
                                        .font(.irisCaption)
                                        .foregroundStyle(IrisPalette.paleTeal)
                    }
                }
            }
        }
    }
                }

                HStack(spacing: 14) {
                    Text("\(session.currentStepIndex)")
                        .font(.irisDisplayM)
                        .foregroundStyle(IrisPalette.tealInk)
                    Text("/\(activeExperiment.steps.count)")
                        .font(.irisBodySmall)
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.35))

                    HStack(spacing: 6) {
                        ForEach(0..<activeExperiment.steps.count, id: \.self) { index in
                            Capsule()
                                .fill(progressColor(for: index))
                                .frame(height: 6)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(IrisPalette.mintMist.opacity(0.45))

                VStack(spacing: 14) {
                    ConnectionStatusRow(statuses: session.connectionStatuses)

                    // ── Live guidance banner from Sehreen's WebSocket ──────────
                    if session.appMode == .live && !session.networkManager.currentGuidanceText.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(IrisPalette.viridian.opacity(0.15))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(IrisPalette.viridian)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.t("IRIS IS SAYING"))
                                    .font(.irisEyebrow)
                                    .tracking(1.2)
                                    .foregroundStyle(IrisPalette.viridian)
                                Text(session.networkManager.currentGuidanceText)
                                    .font(.irisSubheadline)
                                    .foregroundStyle(IrisPalette.tealInk)
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(IrisPalette.mintMist, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(IrisPalette.viridian.opacity(0.2), lineWidth: 1)
                        }
                    }

                    // ── Stream error banner ────────────────────────────────────
                    if session.appMode == .live, let streamError = session.networkManager.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(IrisPalette.flame)
                            Text(streamError)
                                .font(.irisBodySmall)
                                .foregroundStyle(IrisPalette.flame)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(IrisPalette.warmBlush, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            Circle()
                                .fill(IrisPalette.flame)
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Text("\(session.currentStepIndex)")
                                        .font(.irisHeadline)
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(currentStepText)
                                    .font(.irisDisplayM)
                                    .foregroundStyle(IrisPalette.tealInk)
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(session.currentStatus == .error ? IrisPalette.flame : IrisPalette.viridian)
                                        .frame(width: 8, height: 8)
                                    Text(session.t(session.currentStatus == .error ? "Needs review" : "Watching"))
                                        .font(.irisBody)
                                        .foregroundStyle(session.currentStatus == .error ? IrisPalette.flame : IrisPalette.viridian)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(IrisPalette.mintMist.opacity(0.3), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(IrisPalette.flame)
                            .frame(width: 4)
                            .padding(.vertical, 14)
                    }

                    if session.currentStatus == .error {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text(session.t("Error detected"))
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(IrisPalette.flame)

                                Spacer()

                                Text(session.t("Live"))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(IrisPalette.flame.opacity(0.55))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.lastErrorMessage ?? session.t("Correction needed"))
                                    .font(.system(size: 22, weight: .medium, design: .serif))
                                    .foregroundStyle(IrisPalette.tealInk)
                                Text(session.t("Review the issue and acknowledge it when resolved."))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(IrisPalette.flame)
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    session.acknowledgeError()
                                }
                            } label: {
                                Text(session.t("Got it"))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(IrisPalette.flame)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(IrisPalette.flame.opacity(0.1), in: Capsule())
                            }
                        }
                        .padding(20)
                        .background(IrisPalette.warmBlush, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(IrisPalette.flame)
                                .frame(width: 2)
                                .padding(.vertical, 16)
                        }
                    }

                    SectionHeader(label: session.t("Guidance"), color: IrisPalette.viridian)
                        .padding(.horizontal, -18)

                    if !displayTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.t("Transcript"))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(IrisPalette.flame)
                            Text(displayTranscript)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(IrisPalette.tealInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            TextField(session.t("Ask about the current step"), text: $questionDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                session.submitQuestion(questionDraft)
                                questionDraft = ""
                            } label: {
                                Text(session.t("Send"))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 72, height: 44)
                                    .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        if session.appMode == .live {
                            Button {
                                session.advanceCurrentStep()
                            } label: {
                                Label(session.t("Next step"), systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(IrisPalette.viridian, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        } else {
                            HStack(spacing: 10) {
                                Button {
                                    session.advanceCurrentStep()
                                } label: {
                                    Label(session.t("Confirm step"), systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(IrisPalette.viridian, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                TextField(session.t("Flag an issue"), text: $issueDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 14)
                                    .frame(height: 42)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .trailing) {
                                        Button {
                                            session.flagIssue(issueDraft)
                                            issueDraft = ""
                                        } label: {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(IrisPalette.flame)
                                                .padding(.trailing, 12)
                                        }
                                    }
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        if session.guidanceFeed.isEmpty {
                            EmptyStateCard(
                                title: session.t(session.appMode == .live ? "Waiting for backend events" : "No live events yet"),
                                message: session.t(session.appMode == .live ? "Start the experiment stream, ask a question, or advance a step to populate guidance." : "Ask a question, confirm a step, or flag an issue to populate the guidance feed.")
                            )
                        } else {
                            ForEach(session.guidanceFeed.reversed()) { item in
                                GuidanceRow(type: item.type, message: item.message, time: relativeTimeString(from: item.timestamp))
                            }
                        }
                    }
                    .background(IrisPalette.mintMist.opacity(0.3), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(IrisPalette.paleTeal.opacity(0.25), lineWidth: 1)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 150)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                ZStack {
                    if isPressing || session.speechCoordinator.isWakeListening {
                        Circle()
                            .fill((isPressing ? IrisPalette.flame : IrisPalette.coolAqua).opacity(0.18))
                            .frame(width: session.speechCoordinator.isWakeListening ? 94 : 86, height: session.speechCoordinator.isWakeListening ? 94 : 86)
                            .blur(radius: session.speechCoordinator.isWakeListening ? 16 : 12)
                    }

                    Circle()
                        .fill(isPressing ? IrisPalette.flame : (session.speechCoordinator.isWakeListening ? IrisPalette.coolAqua : IrisPalette.tealInk))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle()
                                .stroke(
                                    isPressing ? Color.white.opacity(0.45) : (session.speechCoordinator.isWakeListening ? Color.white.opacity(0.4) : IrisPalette.viridian.opacity(0.35)),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                                .padding(7)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(isPressing || session.speechCoordinator.isWakeListening ? .white : IrisPalette.viridian)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !session.speechCoordinator.isListening {
                                        session.beginListening()
                                    }
                                }
                                .updating($isPressing) { _, state, _ in
                                    state = true
                                }
                                .onEnded { _ in
                                    let spokenQuestion = session.completeListeningTurn()
                                    if !spokenQuestion.isEmpty {
                                        session.submitQuestion(spokenQuestion)
                                    }
                                }
                        )
                        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 8)
                        .scaleEffect(session.speechCoordinator.isWakeListening && !isPressing ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.22), value: session.speechCoordinator.isWakeListening)
                }

                Text(
                    session.speechCoordinator.isListening
                    ? session.t("LISTENING")
                    : (session.speechCoordinator.isWakeListening ? session.t("SAY HEY IRIS OR HOLD TO SPEAK") : session.t("HOLD TO SPEAK"))
                )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(session.speechCoordinator.isListening ? IrisPalette.flame : IrisPalette.viridian.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(session.speechCoordinator.isListening || session.speechCoordinator.isWakeListening ? 0.92 : 0), in: Capsule())

                if let speechError = session.speechCoordinator.errorMessage, !speechError.isEmpty {
                    Text(speechError)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.flame)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
            }
            .padding(.bottom, 94)
        }
    }

    private var currentStepText: String {
        let localizedSteps = activeExperiment.localizedSteps(session.selectedLanguage)
        let safeIndex = min(max(session.currentStepIndex - 1, 0), max(localizedSteps.count - 1, 0))
        return localizedSteps[safeIndex]
    }

    private var displayTranscript: String {
        if session.speechCoordinator.isListening {
            return session.speechCoordinator.liveTranscript
        }
        return session.transcript
    }

    private func progressColor(for index: Int) -> Color {
        if index < session.currentStepIndex - 1 {
            return IrisPalette.viridian
        } else if index == session.currentStepIndex - 1 {
            return IrisPalette.flame
        } else {
            return IrisPalette.paleTeal.opacity(0.3)
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(max(seconds, 1))s"
        }
        return "\(seconds / 60)m"
    }
}

// ── All screens below are unchanged from original ─────────────────────────────

struct ReportScreen: View {
    @ObservedObject var session: AppSession
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        NavBar(
                            title: session.t("Lab report"),
                            label: session.t("REPORT"),
                            onBack: onBack,
                            foreground: .white,
                            compact: true,
                            rightElement: AnyView(
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle")
                                    Text(session.t("Export"))
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(IrisPalette.coolAqua)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(IrisPalette.viridian.opacity(0.2), in: Capsule())
                            )
                        )
                    }
                    .padding(.bottom, 8)
                    .background(IrisPalette.tealInk)

                    HStack {
                        Spacer()
                        if session.reportStatus == .complete {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                Text(session.t("Report complete"))
                            }
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(IrisPalette.viridian)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(IrisPalette.viridian.opacity(0.12), in: Capsule())
                        } else {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 6, height: 6)
                                Text(session.t("Building live..."))
                            }
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(IrisPalette.flame, in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(IrisPalette.mintMist.opacity(0.45))

                    VStack(spacing: 16) {
                    ConnectionStatusRow(statuses: session.connectionStatuses)

                    ReportSection(title: session.t("Procedure followed"), accent: IrisPalette.viridian, background: IrisPalette.mintMist.opacity(0.3), updated: session.generatedReport.procedure.isEmpty ? nil : session.t("Live")) {
                        if session.generatedReport.procedure.isEmpty {
                            Text(session.t("No confirmed steps yet."))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(session.generatedReport.procedure.enumerated()), id: \.offset) { index, step in
                                    reportLine(number: "\(index + 1).", text: step)
                    }
                }
            }
        }
    }

                    ReportSection(title: session.t("Observations"), accent: IrisPalette.coolAqua, background: Color.white, updated: session.generatedReport.observations == "No observations captured yet." ? nil : session.t("Live")) {
                        Text(session.generatedReport.observations)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(IrisPalette.tealInk)
                    }

                    ReportSection(title: session.t("Errors flagged"), accent: IrisPalette.flame, background: IrisPalette.warmBlush, titleColor: IrisPalette.flame, updated: session.generatedReport.errors.isEmpty ? nil : session.t("Live")) {
                        if session.generatedReport.errors.isEmpty {
                            Text(session.t("No issues have been flagged."))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(session.generatedReport.errors, id: \.self) { error in
                                    reportBullet(error, time: "Live")
                                }
                            }
                        }
                    }

                    ReportSection(title: session.t("Key findings"), accent: IrisPalette.viridian, background: IrisPalette.mintMist.opacity(0.3), updated: session.t("Live")) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(session.generatedReport.findings, id: \.self) { finding in
                                reportSimpleBullet(finding)
                            }
                        }
                    }

                    ReportSection(title: session.t("Suggested improvements"), accent: IrisPalette.paleTeal, background: Color.white, updated: session.generatedReport.suggestions.isEmpty ? nil : session.t("Live")) {
                        if session.generatedReport.suggestions.isEmpty {
                            Text(session.t("No suggestions available yet."))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(session.generatedReport.suggestions, id: \.self) { suggestion in
                                    reportSimpleBullet(suggestion)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 140)
            }
        }
        .overlay(alignment: .bottom) {
            ShareLink(item: reportExportText) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(session.t("Export report"))
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: IrisPalette.flame.opacity(0.2), radius: 12, y: 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 92)
        }
        .onAppear {
            session.completeReportBuild()
        }
    }

    private func reportLine(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(IrisPalette.viridian)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(IrisPalette.tealInk)
        }
    }

    private func reportBullet(_ text: String, time: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(IrisPalette.flame)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(IrisPalette.tealInk)
                Text(time)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(IrisPalette.flame)
            }
        }
    }

    private func reportSimpleBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(IrisPalette.flame)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(IrisPalette.tealInk)
        }
    }

    private var reportExportText: String {
        let procedureLines = session.generatedReport.procedure.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let errorLines = session.generatedReport.errors.joined(separator: "\n")
        let findingLines = session.generatedReport.findings.joined(separator: "\n")
        let suggestionLines = session.generatedReport.suggestions.joined(separator: "\n")

        return """
        IRIS Lab Report

        Procedure Followed:
        \(procedureLines.isEmpty ? session.t("No confirmed steps.") : procedureLines)

        Observations:
        \(session.generatedReport.observations)

        Errors Flagged:
        \(errorLines.isEmpty ? session.t("None") : errorLines)

        Key Findings:
        \(findingLines)

        Suggested Improvements:
        \(suggestionLines.isEmpty ? session.t("None") : suggestionLines)
        """
    }
}

struct SettingsScreen: View {
    @ObservedObject var session: AppSession
    @State private var backendURLDraft = ""
    @State private var connectionTestMessage: String?
    @State private var connectionTestSucceeded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                NavBar(title: session.t("Settings"), compact: true)

                SectionHeader(label: session.t("Runtime"), color: IrisPalette.flame, compact: true)
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.t("Choose how IRIS runs during the experiment."))
                        .font(.irisBodySmall)
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.62))

                    HStack(spacing: 8) {
                        modeButton(title: session.t("Demo"), mode: .demo)
                        modeButton(title: session.t("Live"), mode: .live)
                    }

                    Text(session.t(session.appMode == .demo ? "Demo mode stays self-contained for judging." : "Live mode uses Sehreen's backend only for smart-glasses sessions."))
                        .font(.irisCaption)
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                SectionHeader(label: session.t("Appearance"), compact: true)
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(AppearanceMode.allCases) { mode in
                            appearanceButton(mode)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                SectionHeader(label: session.t("Language"), color: IrisPalette.flame, compact: true)
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(AppLanguage.allCases) { language in
                            languageButton(language)
                        }
                    }

                    Text(session.t("UI shell, phone-mode Gemini responses, and spoken guidance follow this language."))
                        .font(.irisCaption)
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                if let user = session.authenticatedUser {
                    SectionHeader(label: session.t("Account"), compact: true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(user.email ?? user.name)
                            .font(.irisBody)
                            .foregroundStyle(IrisPalette.tealInk)

                        Button(action: session.signOut) {
                            Text(session.t("Sign out"))
                                .font(.irisBody)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(IrisPalette.tealInk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                if session.appMode == .live {
                    SectionHeader(label: session.t("Glasses Backend"), compact: true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.t("Used only when IRIS is running with the smart-glasses stream."))
                            .font(.irisBodySmall)
                            .foregroundStyle(IrisPalette.tealInk.opacity(0.62))

                        TextField("192.168.x.x:8000", text: Binding(
                            get: { backendURLDraft },
                            set: { newValue in
                                backendURLDraft = newValue
                                session.networkManager.updateServerAddress(newValue)
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.plain)
                        .font(.irisBody)
                        .foregroundStyle(IrisPalette.tealInk)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(IrisPalette.cleanWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(IrisPalette.paleTeal.opacity(0.7), lineWidth: 1)
                        }

                        Button {
                            Task {
                                let success = await session.networkManager.testConnection()
                                await MainActor.run {
                                    connectionTestSucceeded = success
                                    connectionTestMessage = success
                                        ? session.t("Connected to Sehreen's backend.")
                                        : (session.networkManager.errorMessage ?? session.t("Could not reach the backend."))
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if session.networkManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(session.t(session.networkManager.isLoading ? "Testing..." : "Test connection"))
                                    .font(.irisBody)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(IrisPalette.tealInk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(session.networkManager.isLoading)

                        if let connectionTestMessage {
                            Text(connectionTestMessage)
                                .font(.irisCaption)
                                .foregroundStyle(connectionTestSucceeded ? IrisPalette.viridian : IrisPalette.flame)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                SectionHeader(label: session.t("Data"), color: IrisPalette.flame, compact: true)
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.t("Reset imported procedures and local session history."))
                        .font(.irisBodySmall)
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.62))

                    Button(action: session.clearExperimentHistory) {
                        Text(session.t("Clear experiment history"))
                            .font(.irisBody)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .padding(.bottom, 120)
            }
        }
        .onAppear {
            backendURLDraft = session.networkManager.serverAddress
            connectionTestSucceeded = false
            connectionTestMessage = nil
        }
    }

    private func modeButton(title: String, mode: AppMode) -> some View {
        Button {
            session.updateAppMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(session.appMode == mode ? .white : IrisPalette.tealInk.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(session.appMode == mode ? IrisPalette.flame : IrisPalette.mintMist)
                )
        }
        .buttonStyle(.plain)
    }

    private func appearanceButton(_ mode: AppearanceMode) -> some View {
        Button {
            session.updateAppearanceMode(mode)
        } label: {
            Text(mode.rawValue)
                .font(.irisBody)
                .foregroundStyle(session.appearanceMode == mode ? .white : IrisPalette.tealInk)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(session.appearanceMode == mode ? IrisPalette.viridian : IrisPalette.mintMist.opacity(0.9))
                )
        }
        .buttonStyle(.plain)
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        Button {
            session.updateLanguage(language)
        } label: {
            Text(language.rawValue)
                .font(.irisBody)
                .foregroundStyle(session.selectedLanguage == language ? .white : IrisPalette.tealInk)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(session.selectedLanguage == language ? IrisPalette.flame : Color.white)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(session.selectedLanguage == language ? IrisPalette.flame : IrisPalette.paleTeal.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct BottomTabBar: View {
    @ObservedObject var session: AppSession

    var body: some View {
        HStack {
            tabButton(screen: .home, title: session.t("Home"), icon: "house.fill")
            tabButton(screen: .experiment, title: session.t("Lab"), icon: "flask.fill")
            tabButton(screen: .assistant, title: session.t("Assistant"), icon: "waveform.circle.fill")
            tabButton(screen: .report, title: session.t("Report"), icon: "doc.text.fill")
            tabButton(screen: .settings, title: session.t("Settings"), icon: "slider.horizontal.3")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(IrisTheme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(IrisPalette.paleTeal.opacity(0.22), lineWidth: 1)
        }
    }

    private func tabButton(screen: Screen, title: String, icon: String) -> some View {
        let active = session.activeScreen == screen
        let activeColor = active ? ((session.isLive && screen == .assistant) ? IrisPalette.flame : IrisPalette.viridian) : IrisPalette.viridian.opacity(0.4)

        return Button {
            let leavingLiveFlow = session.isLive &&
                [Screen.experiment, .assistant, .report].contains(session.activeScreen) &&
                [Screen.home, .settings].contains(screen)

            if leavingLiveFlow {
                session.pauseActiveSession()
            }

            if session.currentExperiment == nil, screen == .experiment || screen == .assistant || screen == .report {
                withAnimation(.easeInOut(duration: 0.2)) {
                    session.activeScreen = .home
                }
                return
            }

            if session.isSessionPaused, screen == .assistant || screen == .report || screen == .experiment {
                withAnimation(.easeInOut(duration: 0.2)) {
                    session.activeScreen = .experiment
                }
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                session.activeScreen = screen
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)

                Circle()
                    .fill(active ? activeColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(activeColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct UploadSheet: View {
    @ObservedObject var session: AppSession
    let onClose: () -> Void

    @State private var method = "Paste text"
    @State private var name = ""
    @State private var selectedSubject: Subject = .chemistry
    @State private var selectedDifficulty: Difficulty = .beginner
    @State private var procedureText = ""
    @State private var sourceURL = ""
    @State private var isShowingFileImporter = false
    @State private var isLoadingSource = false
    @State private var importFeedback: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(IrisPalette.flame.opacity(0.5))
                        .frame(width: 28, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 14)

                    HStack {
                        Text(session.t("Add your experiment"))
                            .font(.irisDisplayL)
                            .foregroundStyle(IrisPalette.tealInk)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(IrisPalette.tealInk.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 18)

                    Text(session.t("Upload any procedure. IRIS turns it into a live guided experiment."))
                        .font(.irisBodySmall)
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 14)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            UploadMethodCard(selected: method == "Paste text", icon: "doc.text", title: session.t("Paste text"), subtitle: session.t("Copy-paste your procedure")) {
                                method = "Paste text"
                                importFeedback = nil
                            }

                            UploadMethodCard(selected: method == "PDF", icon: "doc.richtext", title: session.t("Import PDF"), subtitle: session.t("Extract procedure from a PDF")) {
                                method = "PDF"
                                importFeedback = nil
                                isShowingFileImporter = true
                            }

                            UploadMethodCard(selected: method == "URL", icon: "link", title: session.t("Import URL"), subtitle: session.t("Fetch a procedure from the web")) {
                                method = "URL"
                                importFeedback = nil
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                if method == "URL" {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(session.t("Source URL"))
                                            .font(.irisEyebrow)
                                            .tracking(1.2)
                                            .foregroundStyle(IrisPalette.viridian)

                                        HStack(spacing: 10) {
                                            TextField(session.t("https://example.com/lab-procedure"), text: $sourceURL)
                                                .textFieldStyle(.plain)
                                                .font(.irisSubheadline)
                                                .foregroundStyle(IrisPalette.tealInk)
                                                .padding(.horizontal, 14)
                                                .frame(height: 44)
                                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                            Button {
                                                Task {
                                                    await fetchProcedureFromURL()
                                                }
                                            } label: {
                                                Group {
                                                    if isLoadingSource {
                                                        ProgressView()
                                                            .tint(.white)
                                                    } else {
                                                        Text(session.t("Fetch"))
                                                            .font(.irisBody)
                                                    }
                                                }
                                                .foregroundStyle(.white)
                                                .frame(width: 84, height: 44)
                                                .background(IrisPalette.tealInk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            }
                                            .disabled(isLoadingSource || sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }
                                    }
                                }

                                if method == "PDF" {
                                    Button {
                                        isShowingFileImporter = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "doc.richtext")
                                                .foregroundStyle(IrisPalette.flame)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(session.t("Choose PDF"))
                                                    .font(.irisSubheadline)
                                                    .foregroundStyle(IrisPalette.tealInk)
                                                Text(procedureText.isEmpty ? session.t("Select a file to extract its procedure text.") : session.t("PDF text loaded and ready to edit."))
                                                    .font(.irisCaption)
                                                    .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.up.doc")
                                                .foregroundStyle(IrisPalette.viridian)
                                        }
                                        .padding(14)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(IrisPalette.paleTeal.opacity(0.9), lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(session.t("Procedure"))
                                    .font(.irisEyebrow)
                                    .tracking(1.2)
                                    .foregroundStyle(IrisPalette.viridian)

                                ZStack(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white)

                                    if procedureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(procedurePlaceholder)
                                            .font(.irisBody)
                                            .foregroundStyle(IrisPalette.tealInk.opacity(0.35))
                                            .padding(.horizontal, 16)
                                            .padding(.top, 16)
                                    }

                                    TextEditor(text: $procedureText)
                                        .font(.irisSubheadline)
                                        .foregroundStyle(IrisPalette.tealInk)
                                        .scrollContentBackground(.hidden)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(minHeight: 174)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(IrisPalette.paleTeal.opacity(0.9), lineWidth: 1)
                                }

                                if let importFeedback {
                                    Text(importFeedback)
                                        .font(.irisCaption)
                                        .foregroundStyle(
                                            importFeedback == session.t("Loaded PDF text.") ||
                                            importFeedback == session.t("Loaded procedure from URL.")
                                            ? IrisPalette.viridian
                                            : IrisPalette.flame
                                        )
                                }
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                Text(session.t("Experiment details"))
                                    .font(.irisEyebrow)
                                    .tracking(1.2)
                                    .foregroundStyle(IrisPalette.viridian)

                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(session.t("Name"))
                                            .font(.irisCaption)
                                            .foregroundStyle(IrisPalette.tealInk.opacity(0.6))
                                        TextField(session.t("e.g. Acid-base titration"), text: $name)
                                            .textFieldStyle(.plain)
                                            .font(.irisSubheadline)
                                            .padding(.horizontal, 14)
                                            .frame(height: 44)
                                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }

                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(session.t("Subject"))
                                                .font(.irisCaption)
                                                .foregroundStyle(IrisPalette.tealInk.opacity(0.6))
                                            Menu {
                                                ForEach(Subject.allCases) { subject in
                                                    Button(subject.rawValue) {
                                                        selectedSubject = subject
                                                    }
                                                }
                                            } label: {
                                                pickerLabel(selectedSubject.rawValue)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(session.t("Difficulty"))
                                                .font(.irisCaption)
                                                .foregroundStyle(IrisPalette.tealInk.opacity(0.6))
                                            Menu {
                                                ForEach(Difficulty.allCases) { difficulty in
                                                    Button(difficulty.rawValue) {
                                                        selectedDifficulty = difficulty
                                                    }
                                                }
                                            } label: {
                                                pickerLabel(selectedDifficulty.rawValue)
                                            }
                                        }
                                    }
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(IrisPalette.paleTeal.opacity(0.9), lineWidth: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 20)
                    }

                    Button {
                        Task {
                            await prepareImport()
                        }
                    } label: {
                        Text(session.t("Set up experiment"))
                            .font(.irisHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [IrisPalette.flame, IrisPalette.flame.opacity(0.88)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: IrisPalette.flame.opacity(0.2), radius: 14, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .background(Color.white.opacity(0.96))
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: proxy.size.height * 0.78, alignment: .top)
                .background(
                    LinearGradient(
                        colors: [IrisPalette.cleanWhite, IrisPalette.mintMist.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePickedPDF(result)
        }
    }

    private func pickerLabel(_ value: String) -> some View {
        HStack {
            Text(value)
                .font(.irisSubheadline)
                .foregroundStyle(IrisPalette.tealInk)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(IrisPalette.paleTeal)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(IrisPalette.cleanWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var procedurePlaceholder: String {
        switch method {
        case "PDF":
            return session.t("Choose a PDF to extract its procedure text, then adjust it here if needed.")
        case "URL":
            return session.t("Fetch a lab page URL and the extracted procedure will appear here.")
        default:
            return session.t("Paste your lab procedure here. Include steps and, if possible, a materials line.")
        }
    }

    private func prepareImport() async {
        importFeedback = nil

        if method == "URL", procedureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await fetchProcedureFromURL()
        }

        guard !procedureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importFeedback = method == "PDF" ? session.t("Import a PDF first.") : session.t("Add procedure text before continuing.")
            return
        }

        await MainActor.run {
            session.importExperiment(
                name: name,
                subject: selectedSubject,
                difficulty: selectedDifficulty,
                method: method,
                rawText: procedureText
            )
        }
    }

    private func handlePickedPDF(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadPDF(from: url)
        case .failure:
            importFeedback = session.t("Could not open that PDF.")
        }
    }

    private func loadPDF(from url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            importFeedback = session.t("Could not read that PDF.")
            return
        }

        guard let extractedText = session.extractProcedureText(fromPDFData: data) else {
            importFeedback = session.t("That PDF did not contain readable text.")
            return
        }

        procedureText = extractedText
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = session.suggestedExperimentName(
                from: extractedText,
                fallback: url.deletingPathExtension().lastPathComponent
            ) ?? url.deletingPathExtension().lastPathComponent
        }
        importFeedback = session.t("Loaded PDF text.")
    }

    private func fetchProcedureFromURL() async {
        let rawValue = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedURL = session.normalizedImportURL(from: rawValue) else {
            importFeedback = session.t("Enter a valid URL.")
            return
        }

        isLoadingSource = true
        defer { isLoadingSource = false }

        do {
            var request = URLRequest(url: normalizedURL)
            request.timeoutInterval = 20
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""

            let extractedText: String
            if mimeType.contains("pdf") || normalizedURL.pathExtension.lowercased() == "pdf" {
                guard let normalizedText = session.extractProcedureText(fromPDFData: data) else {
                    importFeedback = session.t("Could not parse that PDF URL.")
                    return
                }
                extractedText = normalizedText
            } else {
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
                    importFeedback = session.t("Could not read text from that URL.")
                    return
                }
                extractedText = session.extractProcedureText(fromHTML: html)
            }

            let cleanedText = session.normalizedProcedureText(from: extractedText)
            guard !cleanedText.isEmpty else {
                importFeedback = session.t("That URL did not contain readable procedure text.")
                return
            }

            procedureText = cleanedText
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fallbackName = normalizedURL.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
                name = session.suggestedExperimentName(from: cleanedText, fallback: fallbackName) ?? fallbackName
            }
            importFeedback = session.t("Loaded procedure from URL.")
        } catch {
            importFeedback = session.t("Could not fetch that URL.")
        }
    }
}
