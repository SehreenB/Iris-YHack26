//
//  PrimaryScreens.swift
//  IRIS
//

import AVFoundation
import SwiftUI

struct SplashScreen: View {
    var body: some View {
        ZStack {
            IrisPalette.tealInk
                .ignoresSafeArea()

            IrisLogo(markSize: 76, titleSize: 40, lightStyle: true)
                .scaleEffect(1.02)
        }
    }
}

struct LandingScreen: View {
    let onSignIn: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [IrisPalette.tealInk, IrisPalette.tealInk.opacity(0.96), Color.black.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(IrisPalette.viridian.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: -120, y: -260)

            Circle()
                .fill(IrisPalette.flame.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: 130, y: 280)

            VStack(spacing: 0) {
                Spacer()

                IrisLogo(markSize: 82, titleSize: 42, lightStyle: true)

                Text("Your real-time AI lab teaching assistant. Precision guidance for every experiment.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(IrisPalette.paleTeal)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                    .padding(.top, 28)

                Spacer()

                VStack(spacing: 14) {
                    Button(action: onSignIn) {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(IrisPalette.tealInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    Button(action: onSignIn) {
                        Text("Create an account")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(IrisPalette.paleTeal.opacity(0.35), lineWidth: 1)
                            )
                    }

                    Text("By continuing, you agree to our Terms of Service and Privacy Policy.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.paleTeal.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
    }
}

struct OnboardingScreen: View {
    @Binding var step: Int
    let onComplete: () -> Void

    private let slides: [OnboardingSlide] = [
        .init(title: "Real-time AI Guidance", description: "IRIS monitors your experiment through your camera, providing step-by-step guidance as you work.", icon: "camera.fill", tint: IrisPalette.viridian),
        .init(title: "Smart Lab Assistant", description: "Ask questions anytime. IRIS understands your procedure and helps you troubleshoot in real-time.", icon: "sparkles", tint: IrisPalette.flame),
        .init(title: "Automated Reporting", description: "Focus on the science. IRIS automatically captures data and generates a comprehensive lab report for you.", icon: "doc.text.fill", tint: IrisPalette.coolAqua)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            let slide = slides[step]

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(slide.tint.opacity(0.12))
                    .frame(width: 92, height: 92)
                    .overlay {
                        Image(systemName: slide.icon)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(slide.tint)
                    }

                VStack(spacing: 14) {
                    Text(slide.title)
                        .font(.system(size: 30, weight: .medium, design: .serif))
                        .foregroundStyle(IrisPalette.tealInk)
                        .multilineTextAlignment(.center)

                    Text(slide.description)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)
                }

                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? IrisPalette.flame : IrisPalette.paleTeal.opacity(0.3))
                            .frame(width: index == step ? 28 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    if step < slides.count - 1 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step += 1
                        }
                    } else {
                        onComplete()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(step == slides.count - 1 ? "Get Started" : "Next")
                            .fontWeight(.bold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(IrisPalette.tealInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                if step < slides.count - 1 {
                    Button("Skip intro", action: onComplete)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .background(IrisPalette.cleanWhite.ignoresSafeArea())
    }
}

struct HomeScreen: View {
    let experiments: [Experiment]
    let onStartExperiment: (Experiment) -> Void
    let onUpload: () -> Void

    @State private var search = ""

    private var filteredExperiments: [Experiment] {
        guard !search.isEmpty else { return experiments }
        return experiments.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.subject.rawValue.localizedCaseInsensitiveContains(search)
        }
    }

    private var featuredExperiments: [Experiment] {
        filteredExperiments.filter { !$0.isUploaded }
    }

    private var uploadedExperiments: [Experiment] {
        filteredExperiments.filter(\.isUploaded)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    NavBar(isHome: true)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(IrisPalette.coolAqua)

                        TextField("Search experiments...", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(IrisPalette.paleTeal.opacity(0.65), lineWidth: 1)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                .background(IrisPalette.mintMist.opacity(0.3))

                Button(action: onUpload) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bring your own procedure")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("Upload, paste, or link")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(IrisPalette.peach)
                        }
                        .foregroundStyle(Color.white)

                        Spacer()

                        Circle()
                            .fill(Color.white)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(IrisPalette.flame)
                            }
                    }
                    .padding(16)
                    .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: IrisPalette.flame.opacity(0.22), radius: 18, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, -12)
                .padding(.bottom, 18)

                SectionHeader(label: "Subjects", count: "6 areas")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Subject.allCases) { subject in
                            VStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(IrisPalette.paleTeal.opacity(0.25))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Image(systemName: subject.icon)
                                            .foregroundStyle(IrisPalette.viridian)
                                    }

                                VStack(spacing: 3) {
                                    Text(subject.rawValue)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(IrisPalette.tealInk)
                                    Text("\(subject.count)")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(IrisPalette.flame)
                                }
                            }
                            .frame(width: 104, height: 118)
                            .background(IrisPalette.mintMist.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(IrisPalette.paleTeal.opacity(0.4), lineWidth: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }

                if !featuredExperiments.isEmpty {
                    SectionHeader(label: "Featured", count: "\(featuredExperiments.count) experiment\(featuredExperiments.count == 1 ? "" : "s")", color: IrisPalette.flame)

                    VStack(spacing: 12) {
                        ForEach(Array(featuredExperiments.enumerated()), id: \.element.id) { index, experiment in
                            ExperimentCard(experiment: experiment, isDark: index == 0, onStart: { onStartExperiment(experiment) })
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)
                }

                SectionHeader(label: "Your experiments", count: "\(uploadedExperiments.count)")

                if uploadedExperiments.isEmpty {
                    EmptyStateCard(title: "No experiments yet", message: "Import a procedure to create your first lab flow.")
                        .padding(.horizontal, 18)
                        .padding(.bottom, 120)
                } else {
                    VStack(spacing: 12) {
                        ForEach(uploadedExperiments) { experiment in
                            ExperimentCard(experiment: experiment, isDark: false, onStart: { onStartExperiment(experiment) })
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 120)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: onUpload) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 54, height: 54)
                    .background(IrisPalette.flame, in: Circle())
                    .shadow(color: IrisPalette.flame.opacity(0.35), radius: 16, y: 10)
            }
            .padding(.trailing, 22)
            .padding(.bottom, 96)
        }
    }
}

struct ExperimentSetupScreen: View {
    let experiment: Experiment
    @ObservedObject var session: AppSession
    let onBack: () -> Void
    let onStart: () -> Void

    @State private var cameraMode = "Phone"
    @State private var phoneSide = "Rear"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    NavBar(
                        title: experiment.name,
                        onBack: onBack,
                        foreground: .white,
                        compact: true,
                        rightElement: AnyView(
                            Text(experiment.subject.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(IrisPalette.coolAqua)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(IrisPalette.viridian.opacity(0.2), in: Capsule())
                        )
                    )
                }
                .padding(.bottom, 8)
                .background(IrisPalette.tealInk)

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(label: "Camera", color: IrisPalette.flame)

                    ConnectionStatusRow(statuses: [
                        .init(label: "Camera", value: cameraStatusValue, color: IrisPalette.viridian),
                        .init(label: "Mode", value: cameraMode, color: IrisPalette.flame),
                        .init(label: "Lens", value: cameraMode == "Phone" ? phoneSide : "Remote", color: IrisPalette.coolAqua)
                    ])
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                    Group {
                        if cameraMode == "Phone" {
                            ZStack {
                                CameraPreviewView(session: session.cameraManager.session)

                                if session.cameraManager.authorizationStatus != .authorized || !session.cameraManager.isSessionRunning {
                                    previewOverlay(
                                        icon: session.cameraManager.authorizationStatus == .denied ? "camera.slash.fill" : "camera.fill",
                                        title: session.cameraManager.authorizationStatus == .denied ? "Camera access blocked" : "Preparing camera",
                                        subtitle: session.cameraManager.errorMessage ?? "IRIS is requesting camera access and starting the live preview."
                                    )
                                }
                            }
                        } else {
                            previewOverlay(
                                icon: "network",
                                title: "Waiting for glasses stream",
                                subtitle: "Connect the external camera feed from your ESP32 or relay backend before starting."
                            )
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(IrisPalette.paleTeal.opacity(0.24), lineWidth: 1)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)

                    HStack(spacing: 14) {
                        setupCameraCard(title: "Phone", subtitle: "Device camera", icon: "iphone", selected: cameraMode == "Phone") {
                            cameraMode = "Phone"
                            session.prepareCamera(position: phoneSide == "Front" ? .front : .back)
                        }

                        setupCameraCard(title: "Glasses", subtitle: "External stream", icon: "eyeglasses", selected: cameraMode == "Glasses") {
                            cameraMode = "Glasses"
                            session.useExternalCameraSource()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)

                    if cameraMode == "Phone" {
                        HStack(spacing: 8) {
                            ForEach(["Front", "Rear"], id: \.self) { side in
                                Button {
                                    phoneSide = side
                                    session.prepareCamera(position: side == "Front" ? .front : .back)
                                } label: {
                                    Text(side.uppercased())
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(phoneSide == side ? .white : IrisPalette.tealInk.opacity(0.55))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(phoneSide == side ? IrisPalette.flame : Color.clear)
                                        )
                                }
                            }
                        }
                        .padding(5)
                        .background(IrisPalette.mintMist.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 26)
                    }

                    SectionHeader(label: "Procedure")

                    VStack(spacing: 18) {
                        ForEach(Array(experiment.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(IrisPalette.viridian)
                                        .frame(width: 30, height: 30)
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }

                                Text(step)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(IrisPalette.tealInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    .padding(.bottom, 26)

                    SectionHeader(label: "Materials")

                    FlowLayout(experiment.materials, spacing: 10) { material in
                        Text(material)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(IrisPalette.tealInk)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background(IrisPalette.mintMist, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(IrisPalette.paleTeal.opacity(0.35), lineWidth: 1)
                            }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 140)
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                Button(action: onStart) {
                    Circle()
                        .fill(IrisPalette.flame)
                        .frame(width: 70, height: 70)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .padding(7)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: IrisPalette.flame.opacity(0.3), radius: 18, y: 10)
                }

                Text("START LAB")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(IrisPalette.flame)
            }
            .padding(.bottom, 96)
        }
        .task {
            guard cameraMode == "Phone" else { return }
            session.prepareCamera(position: phoneSide == "Front" ? .front : .back)
        }
    }

    private var cameraStatusValue: String {
        if cameraMode == "Glasses" {
            return "External"
        }
        switch session.cameraManager.authorizationStatus {
        case .authorized:
            return session.cameraManager.isSessionRunning ? "Connected" : "Starting"
        case .notDetermined:
            return "Pending"
        case .denied, .restricted:
            return "Denied"
        @unknown default:
            return "Unknown"
        }
    }

    private func previewOverlay(icon: String, title: String, subtitle: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [IrisPalette.tealInk, IrisPalette.tealInk.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Circle()
                    .fill(IrisPalette.viridian.opacity(0.16))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(IrisPalette.viridian)
                    }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.paleTeal)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private func setupCameraCard(title: String, subtitle: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? IrisPalette.flame : IrisPalette.paleTeal.opacity(0.35))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(selected ? .white : IrisPalette.viridian)
                    }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(selected ? IrisPalette.warmBlush : IrisPalette.mintMist.opacity(0.45), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(selected ? IrisPalette.flame : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}
