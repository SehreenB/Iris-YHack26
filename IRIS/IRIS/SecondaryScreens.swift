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

struct AssistantScreen: View {
    let experiment: Experiment
    @ObservedObject var session: AppSession
    let onEnd: () -> Void

    @GestureState private var isPressing = false
    @State private var questionDraft = ""
    @State private var issueDraft = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    NavBar(
                        title: experiment.name,
                        label: "LIVE SESSION",
                        foreground: .white,
                        compact: true,
                        rightElement: AnyView(
                            HStack(spacing: 10) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 6, height: 6)
                                    Text("Live")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
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
                    if session.isUsingExternalCamera {
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(IrisPalette.tealInk)
                            .frame(height: 240)

                        VStack(spacing: 10) {
                            Circle()
                                .fill(IrisPalette.viridian.opacity(0.15))
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Image(systemName: "network")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundStyle(IrisPalette.viridian)
                                }

                            Text(session.cameraSource)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
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
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(IrisPalette.viridian)

                                if let errorMessage = session.cameraManager.errorMessage, !errorMessage.isEmpty {
                                    Text(errorMessage)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(IrisPalette.paleTeal)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 14) {
                    Text("\(session.currentStepIndex)")
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(IrisPalette.tealInk)
                    Text("/\(experiment.steps.count)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.35))

                    HStack(spacing: 6) {
                        ForEach(0..<experiment.steps.count, id: \.self) { index in
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
                                Text("IRIS IS SAYING")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundStyle(IrisPalette.viridian)
                                Text(session.networkManager.currentGuidanceText)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
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
                                .font(.system(size: 12, weight: .medium, design: .rounded))
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
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(currentStepText)
                                    .font(.system(size: 21, weight: .medium, design: .serif))
                                    .foregroundStyle(IrisPalette.tealInk)
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(session.currentStatus == .error ? IrisPalette.flame : IrisPalette.viridian)
                                        .frame(width: 8, height: 8)
                                    Text(session.currentStatus == .error ? "Needs review" : "Watching")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
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
                                    Text("Error detected")
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(IrisPalette.flame)

                                Spacer()

                                Text("Live")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(IrisPalette.flame.opacity(0.55))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.lastErrorMessage ?? "Correction needed")
                                    .font(.system(size: 22, weight: .medium, design: .serif))
                                    .foregroundStyle(IrisPalette.tealInk)
                                Text("Review the issue and acknowledge it when resolved.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(IrisPalette.flame)
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    session.acknowledgeError()
                                }
                            } label: {
                                Text("Got it")
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

                    SectionHeader(label: "Guidance", color: IrisPalette.viridian)
                        .padding(.horizontal, -18)

                    if !displayTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transcript")
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
                            TextField("Ask about the current step", text: $questionDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                session.submitQuestion(questionDraft)
                                questionDraft = ""
                            } label: {
                                Text("Send")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 72, height: 44)
                                    .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                session.advanceCurrentStep()
                            } label: {
                                Label("Confirm step", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(IrisPalette.viridian, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            TextField("Flag an issue", text: $issueDraft)
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

                    VStack(spacing: 0) {
                        if session.guidanceFeed.isEmpty {
                            EmptyStateCard(title: "No live events yet", message: "Ask a question, confirm a step, or flag an issue to populate the guidance feed.")
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
                    if isPressing {
                        Circle()
                            .fill(IrisPalette.flame.opacity(0.18))
                            .frame(width: 86, height: 86)
                            .blur(radius: 12)
                    }

                    Circle()
                        .fill(isPressing ? IrisPalette.flame : IrisPalette.tealInk)
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle()
                                .stroke(
                                    isPressing ? Color.white.opacity(0.45) : IrisPalette.viridian.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                                .padding(7)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(isPressing ? .white : IrisPalette.viridian)
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
                }

                Text(session.speechCoordinator.isListening ? "LISTENING" : "HOLD TO SPEAK")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(session.speechCoordinator.isListening ? IrisPalette.flame : IrisPalette.viridian.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(session.speechCoordinator.isListening ? 0.92 : 0), in: Capsule())
            }
            .padding(.bottom, 94)
        }
    }

    private var currentStepText: String {
        let safeIndex = min(max(session.currentStepIndex - 1, 0), max(experiment.steps.count - 1, 0))
        return experiment.steps[safeIndex]
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    NavBar(
                        title: "Lab report",
                        label: "REPORT",
                        onBack: onBack,
                        foreground: .white,
                        compact: true,
                        rightElement: AnyView(
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                Text("Export")
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
                            Text("Report complete")
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
                            Text("Building live...")
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

                    ReportSection(title: "Procedure followed", accent: IrisPalette.viridian, background: IrisPalette.mintMist.opacity(0.3), updated: session.generatedReport.procedure.isEmpty ? nil : "Live") {
                        if session.generatedReport.procedure.isEmpty {
                            Text("No confirmed steps yet.")
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

                    ReportSection(title: "Observations", accent: IrisPalette.coolAqua, background: Color.white, updated: session.generatedReport.observations == "No observations captured yet." ? nil : "Live") {
                        Text(session.generatedReport.observations)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(IrisPalette.tealInk)
                    }

                    ReportSection(title: "Errors flagged", accent: IrisPalette.flame, background: IrisPalette.warmBlush, titleColor: IrisPalette.flame, updated: session.generatedReport.errors.isEmpty ? nil : "Live") {
                        if session.generatedReport.errors.isEmpty {
                            Text("No issues have been flagged.")
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

                    ReportSection(title: "Key findings", accent: IrisPalette.viridian, background: IrisPalette.mintMist.opacity(0.3), updated: "Live") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(session.generatedReport.findings, id: \.self) { finding in
                                reportSimpleBullet(finding)
                            }
                        }
                    }

                    ReportSection(title: "Suggested improvements", accent: IrisPalette.paleTeal, background: Color.white, updated: session.generatedReport.suggestions.isEmpty ? nil : "Live") {
                        if session.generatedReport.suggestions.isEmpty {
                            Text("No suggestions available yet.")
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
                    Text("Export report")
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
        \(procedureLines.isEmpty ? "No confirmed steps." : procedureLines)

        Observations:
        \(session.generatedReport.observations)

        Errors Flagged:
        \(errorLines.isEmpty ? "None" : errorLines)

        Key Findings:
        \(findingLines)

        Suggested Improvements:
        \(suggestionLines.isEmpty ? "None" : suggestionLines)
        """
    }
}

struct SettingsScreen: View {
    @ObservedObject var session: AppSession
    @State private var backendURLDraft = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                NavBar(title: "Settings", compact: true)

                SectionHeader(label: "Mode", color: IrisPalette.flame, compact: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hackathon runtime")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk)

                    HStack(spacing: 8) {
                        modeButton(title: "Demo", mode: .demo)
                        modeButton(title: "Live", mode: .live)
                    }

                    Text(session.appMode == .demo ? "Uses safe local fallback responses for judging." : "Uses Sehreen's start-experiment, websocket stream, and advance-step flow.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.5))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Divider().overlay(IrisPalette.mintMist)
                }

                SectionHeader(label: "Server", color: IrisPalette.flame, compact: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Backend address (Sehreen's laptop)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk)

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
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(IrisPalette.cleanWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(IrisPalette.paleTeal.opacity(0.7), lineWidth: 1)
                    }

                    Text("WebSocket target: \(session.networkManager.websocketTarget)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.45))
                        .lineLimit(2)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Divider().overlay(IrisPalette.mintMist)
                }

                SectionHeader(label: "Camera", compact: true)
                SettingsRow(label: "Default lens", value: session.cameraSource, compact: true)
                SettingsRow(label: "Auto-focus", toggle: true, compact: true)

                SectionHeader(label: "Voice", color: IrisPalette.flame, compact: true)
                SettingsRow(label: "IRIS Voice", value: "Kore", compact: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Voice speed")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk)

                    HStack(spacing: 4) {
                        ForEach(["0.8x", "1.0x", "1.2x", "1.5x"], id: \.self) { speed in
                            Text(speed)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(speed == "1.0x" ? .white : IrisPalette.tealInk.opacity(0.55))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(speed == "1.0x" ? IrisPalette.flame : Color.clear)
                                )
                        }
                    }
                    .padding(4)
                    .background(IrisPalette.mintMist, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Divider().overlay(IrisPalette.mintMist)
                }

                SectionHeader(label: "Experiments", compact: true)

                VStack(alignment: .leading, spacing: 12) {
                    Text("My uploads")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk)

                    if session.experiments.filter(\.isUploaded).isEmpty {
                        EmptyStateCard(title: "No uploads saved", message: "Imported procedures will appear here.")
                    } else {
                        ForEach(session.experiments.filter(\.isUploaded)) { experiment in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(experiment.name)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(IrisPalette.tealInk)
                                            .lineLimit(1)

                                        Text("Uploaded")
                                            .font(.system(size: 8, weight: .medium, design: .rounded))
                                            .foregroundStyle(IrisPalette.flame)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(IrisPalette.warmBlush, in: Capsule())
                                    }

                                    HStack(spacing: 8) {
                                        Text(experiment.subject.rawValue)
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(IrisPalette.viridian)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(IrisPalette.mintMist, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                        Text(experiment.createdAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(IrisPalette.flame)
                                    }
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(IrisPalette.paleTeal.opacity(0.65), lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                SectionHeader(label: "About", color: IrisPalette.flame, compact: true)

                VStack(spacing: 12) {
                    Button(action: session.clearExperimentHistory) {
                        Text("Clear experiment history")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(spacing: 4) {
                        Text("v1.0.4")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(IrisPalette.flame)
                        Text("IRIS · YHacks 2026")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        Text("GitHub Repository")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(IrisPalette.coolAqua)
                            .underline()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .padding(.bottom, 120)
            }
        }
        .onAppear {
            backendURLDraft = session.networkManager.serverAddress
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
}

struct BottomTabBar: View {
    @ObservedObject var session: AppSession

    var body: some View {
        HStack {
            tabButton(screen: .home, title: "Home", icon: "house.fill")
            tabButton(screen: .experiment, title: "Lab", icon: "flask.fill")
            tabButton(screen: .assistant, title: "Assistant", icon: "sparkles")
            tabButton(screen: .report, title: "Report", icon: "doc.text.fill")
            tabButton(screen: .settings, title: "Settings", icon: "slider.horizontal.3")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(IrisPalette.paleTeal.opacity(0.22), lineWidth: 1)
        }
    }

    private func tabButton(screen: Screen, title: String, icon: String) -> some View {
        let active = session.activeScreen == screen
        let activeColor = active ? ((session.isLive && screen == .assistant) ? IrisPalette.flame : IrisPalette.viridian) : IrisPalette.viridian.opacity(0.4)

        return Button {
            if session.currentExperiment == nil, screen == .experiment || screen == .assistant || screen == .report {
                withAnimation(.easeInOut(duration: 0.2)) {
                    session.activeScreen = .home
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

    @State private var method = "Upload a file"
    @State private var name = ""
    @State private var selectedSubject: Subject = .chemistry
    @State private var selectedDifficulty: Difficulty = .beginner
    @State private var procedureText = """
1. Pour liquid from flask A into the beaker
2. Add exactly 3 drops of indicator solution
3. Slowly add liquid from flask B until colour change
Materials: Flask A, Flask B, Beaker, Indicator solution, Dropper
"""

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
                        Text("Add your experiment")
                            .font(.system(size: 24, weight: .medium, design: .serif))
                            .foregroundStyle(IrisPalette.tealInk)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(IrisPalette.tealInk.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 18)

                    Text("Upload any procedure. IRIS turns it into a live guided experiment.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            UploadMethodCard(selected: method == "Upload a file", icon: "arrow.up.doc", title: "Upload a file", subtitle: ".pdf · .docx · .txt") {
                                method = "Upload a file"
                            }
                            UploadMethodCard(selected: method == "Paste text", icon: "doc.text", title: "Paste text", subtitle: "Copy-paste your procedure") {
                                method = "Paste text"
                            }
                            UploadMethodCard(selected: method == "Enter URL", icon: "globe", title: "Enter URL", subtitle: "Link to a lab website") {
                                method = "Enter URL"
                            }

                            if method == "Paste text" {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Procedure text")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .tracking(1)
                                        .foregroundStyle(IrisPalette.tealInk)

                                    TextEditor(text: $procedureText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(IrisPalette.tealInk)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 150)
                                        .padding(10)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(IrisPalette.paleTeal, lineWidth: 1)
                                        }
                                }
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Experiment name")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .tracking(1)
                                        .foregroundStyle(IrisPalette.tealInk)
                                    TextField("e.g. Acid-base titration", text: $name)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 14)
                                        .frame(height: 42)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(IrisPalette.paleTeal, lineWidth: 1)
                                        }
                                }

                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Subject")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .tracking(1)
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
                                        Text("Difficulty")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .tracking(1)
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
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }

                    Button {
                        session.importExperiment(
                            name: name,
                            subject: selectedSubject,
                            difficulty: selectedDifficulty,
                            method: method,
                            rawText: procedureText
                        )
                    } label: {
                        Text("Parse and set up experiment")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(18)
                    .background(Color.white)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: proxy.size.height * 0.78, alignment: .top)
                .background(IrisPalette.mintMist, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func pickerLabel(_ value: String) -> some View {
        HStack {
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(IrisPalette.tealInk)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(IrisPalette.paleTeal)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(IrisPalette.paleTeal, lineWidth: 1)
        }
    }
}
