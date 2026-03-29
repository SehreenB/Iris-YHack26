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
    let onContinueAsGuest: () -> Void
    let isSigningIn: Bool
    let errorMessage: String?
    @AppStorage("iris.settings.language") private var languageRawValue = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

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

                VStack(spacing: -34) {
                    Image("logotop")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 148)

                    Image("logobottom")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 210)
                }
                .padding(.top, 96)

                Text(language.localized("Your real-time AI lab teaching assistant. Precision guidance for every experiment."))
                    .font(.custom("Baskerville", size: 21))
                    .foregroundStyle(IrisPalette.paleTeal)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 24)

                Spacer()

                VStack(spacing: 14) {
                    Button(action: onSignIn) {
                        HStack(spacing: 12) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(IrisPalette.tealInk)
                            } else {
                                Image(systemName: "globe")
                            }
                            Text(language.localized(isSigningIn ? "Signing in..." : "Continue with Google"))
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(IrisPalette.tealInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .disabled(isSigningIn)

                    Button(action: onContinueAsGuest) {
                        Text(language.localized("New here? Set up your workspace"))
                            .font(.irisSubheadline)
                            .foregroundStyle(IrisPalette.paleTeal.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.irisCaption)
                            .foregroundStyle(IrisPalette.peach)
                            .multilineTextAlignment(.center)
                    }

                    Text(language.localized("By continuing, you agree to our Terms of Service and Privacy Policy."))
                        .font(.irisCaption)
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
    @AppStorage("iris.settings.language") private var languageRawValue = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

    private let slides: [OnboardingSlide] = [
        .init(title: "Real-time AI Guidance", description: "IRIS monitors your experiment through your camera, providing step-by-step guidance as you work.", icon: "camera.fill", tint: IrisPalette.viridian),
        .init(title: "Smart Lab Assistant", description: "Ask questions anytime. IRIS understands your procedure and helps you troubleshoot in real-time.", icon: "waveform.circle.fill", tint: IrisPalette.flame),
        .init(title: "Automated Reporting", description: "Focus on the science. IRIS automatically captures data and generates a comprehensive lab report for you.", icon: "doc.text.fill", tint: IrisPalette.coolAqua)
    ]

    private func advanceStep() {
        if step < slides.count - 1 {
            withAnimation(.easeInOut(duration: 0.25)) {
                step += 1
            }
        } else {
            onComplete()
        }
    }

    private func goBackStep() {
        guard step > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            step -= 1
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactWidth = proxy.size.width < 390
            let contentWidth = min(proxy.size.width - 40, 420.0)
            let slide = slides[step]

            ZStack {
                IrisTheme.background
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        slide.tint.opacity(0.12),
                        IrisPalette.cleanWhite.opacity(0.0),
                        IrisPalette.flame.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(slide.tint.opacity(0.14))
                    .frame(width: proxy.size.width * 0.72, height: proxy.size.width * 0.72)
                    .blur(radius: 36)
                    .offset(x: -proxy.size.width * 0.22, y: -proxy.size.height * 0.18)

                Circle()
                    .fill(IrisPalette.flame.opacity(0.1))
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.width * 0.62)
                    .blur(radius: 48)
                    .offset(x: proxy.size.width * 0.24, y: proxy.size.height * 0.24)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: isCompactWidth ? 28 : 32) {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(slide.tint.opacity(0.14))
                            .frame(width: isCompactWidth ? 132 : 148, height: isCompactWidth ? 132 : 148)
                            .overlay {
                                Image(systemName: slide.icon)
                                    .font(.system(size: isCompactWidth ? 52 : 58, weight: .semibold))
                                    .foregroundStyle(slide.tint)
                            }

                        VStack(spacing: 16) {
                            Text(language.localized(slide.title))
                                .font(.custom("Didot", size: isCompactWidth ? 38 : 42))
                                .foregroundStyle(IrisTheme.primaryText)
                                .multilineTextAlignment(.center)

                            Text(language.localized(slide.description))
                                .font(.system(size: isCompactWidth ? 18 : 19, weight: .medium, design: .rounded))
                                .foregroundStyle(IrisTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: contentWidth)
                        }

                        HStack(spacing: 10) {
                            ForEach(slides.indices, id: \.self) { index in
                                Capsule()
                                    .fill(index == step ? IrisPalette.flame : IrisPalette.paleTeal.opacity(0.3))
                                    .frame(width: index == step ? 30 : 9, height: 8)
                                    .animation(.easeInOut(duration: 0.2), value: step)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        Text(language.localized(step == slides.count - 1 ? "Swipe left to enter IRIS" : "Swipe left to continue"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(IrisTheme.secondaryText)

                        HStack(spacing: 10) {
                            ForEach(slides.indices, id: \.self) { index in
                                Capsule()
                                    .fill(index == step ? IrisPalette.flame : IrisPalette.paleTeal.opacity(0.3))
                                    .frame(width: index == step ? 30 : 9, height: 8)
                                    .animation(.easeInOut(duration: 0.2), value: step)
                            }
                        }

                        if step < slides.count - 1 {
                            Button(language.localized("Skip intro"), action: onComplete)
                                .font(.irisSubheadline)
                                .foregroundStyle(IrisTheme.secondaryText)
                                .buttonStyle(.plain)
                        } else {
                            Button(language.localized("Enter IRIS"), action: onComplete)
                                .font(.irisSubheadline)
                                .foregroundStyle(IrisTheme.primaryText)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                advanceStep()
                            } else if value.translation.width > 40 {
                                goBackStep()
                            }
                        }
                )
            }
        }
    }
}

struct HomeScreen: View {
    @ObservedObject var session: AppSession
    @ObservedObject var networkManager: NetworkManager
    let experiments: [Experiment]
    let onStartExperiment: (Experiment) -> Void
    let onUpload: () -> Void

    @State private var search = ""

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredExperiments: [Experiment] {
        guard !trimmedSearch.isEmpty else { return experiments }
        return experiments.filter {
            $0.localizedName(session.selectedLanguage).localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.localizedDescription(session.selectedLanguage).localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.subject.localizedName(session.selectedLanguage).localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var remoteSearchResults: [Experiment] {
        guard !trimmedSearch.isEmpty, session.remoteSearchQuery == trimmedSearch else { return [] }
        return session.remoteSearchResults
    }

    private var featuredExperiments: [Experiment] {
        if !remoteSearchResults.isEmpty {
            return remoteSearchResults
        }
        return filteredExperiments.filter { !$0.isUploaded }
    }

    private var uploadedExperiments: [Experiment] {
        filteredExperiments.filter(\.isUploaded)
    }

    private var experimentSectionTitle: String {
        session.t(trimmedSearch.isEmpty ? "Featured" : "Search results")
    }

    private var experimentSectionCount: String {
        let noun = featuredExperiments.count == 1 ? session.t("experiment") : session.t("experiments")
        return "\(featuredExperiments.count) \(noun)"
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactWidth = proxy.size.width < 390
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = min(max(proxy.size.width * 0.96, 360), isCompactWidth ? 405 : 450) + topInset
            let sidePadding: CGFloat = isCompactWidth ? 16 : 18
            let contentMaxWidth = min(proxy.size.width - (sidePadding * 2), 430)
            let actionButtonSize: CGFloat = isCompactWidth ? 40 : 44
            let searchHeight: CGFloat = isCompactWidth ? 52 : 58
            let searchFontSize: CGFloat = isCompactWidth ? 13 : 14
            let uploadTopOffset: CGFloat = isCompactWidth ? -18 : -24
            let uploadIconSize: CGFloat = isCompactWidth ? 38 : 40
            let uploadArrowSize: CGFloat = isCompactWidth ? 28 : 30

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        labHeroBackground

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top) {
                                Image("logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: isCompactWidth ? 146 : 168, height: isCompactWidth ? 56 : 64, alignment: .leading)

                                Spacer()

                                Button(action: onUpload) {
                                    Image(systemName: "plus")
                                        .font(.system(size: isCompactWidth ? 18 : 20, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: actionButtonSize, height: actionButtonSize)
                                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(.white.opacity(0.14), lineWidth: 1)
                                        }
                                }
                            }
                            .frame(maxWidth: contentMaxWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sidePadding)
                            .padding(.top, topInset + (isCompactWidth ? 12 : 16))

                            Spacer()

                            VStack(alignment: .leading, spacing: isCompactWidth ? 8 : 10) {
                                Text(session.t("LAB ASSISTANT"))
                                    .font(.irisEyebrow)
                                    .tracking(isCompactWidth ? 1.6 : 2)
                                    .foregroundStyle(IrisPalette.coolAqua.opacity(0.82))

                                Text(session.t("What are we\nexperimenting?"))
                                    .font(isCompactWidth ? .irisDisplayL : .irisDisplayXL)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.28), radius: 12, y: 3)
                                    .lineSpacing(isCompactWidth ? 1 : 2)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(IrisPalette.coolAqua.opacity(0.78))

                                    ZStack(alignment: .leading) {
                                        if search.isEmpty {
                                            Text(session.t("Search experiments..."))
                                                .font(searchFontSize <= 13 ? .irisBody : .irisSubheadline)
                                                .foregroundStyle(.white.opacity(0.82))
                                                .shadow(color: .black.opacity(0.22), radius: 8, y: 1)
                                        }

                                        TextField("", text: $search)
                                            .textFieldStyle(.plain)
                                            .font(searchFontSize <= 13 ? .irisBody : .irisSubheadline)
                                            .foregroundStyle(.white)
                                            .tint(.white)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: searchHeight)
                                .background(IrisPalette.tealInk.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                            }
                            .frame(maxWidth: contentMaxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sidePadding)
                            .padding(.bottom, isCompactWidth ? 26 : 34)
                        }
                    }
                    .frame(height: heroHeight)

                    Button(action: onUpload) {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .frame(width: uploadIconSize, height: uploadIconSize)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: isCompactWidth ? 20 : 22, weight: .bold))
                                        .foregroundStyle(Color.white)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.t("Bring your own procedure"))
                                    .font(.irisSubheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text(session.t("Upload, paste, or link"))
                                    .font(.irisBodySmall)
                                    .foregroundStyle(IrisPalette.peach)
                            }
                            .foregroundStyle(Color.white)

                            Spacer(minLength: 8)

                            Circle()
                                .fill(Color.white)
                                .frame(width: uploadArrowSize, height: uploadArrowSize)
                                .overlay {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(IrisPalette.flame)
                                }
                        }
                        .padding(isCompactWidth ? 12 : 13)
                        .background(IrisPalette.flame, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: IrisPalette.flame.opacity(0.18), radius: 14, y: 8)
                    }
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, sidePadding)
                    .padding(.top, uploadTopOffset)
                    .padding(.bottom, 14)

                    SectionHeader(label: session.t("Subjects"), count: session.t("6 areas"))
                        .frame(maxWidth: contentMaxWidth)
                        .frame(maxWidth: .infinity, alignment: .center)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(Subject.allCases.prefix(3)) { subject in
                                SubjectImageCard(subject: subject, cardWidth: isCompactWidth ? 154 : 166)
                            }
                        }
                        .padding(.horizontal, sidePadding)
                    }
                    .padding(.bottom, 18)

                    if !trimmedSearch.isEmpty, networkManager.isSearching {
                        Text(session.t("Searching with Gemini…"))
                            .font(.irisCaption)
                            .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                            .frame(maxWidth: contentMaxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sidePadding)
                            .padding(.bottom, 8)
                    } else if !trimmedSearch.isEmpty,
                              featuredExperiments.isEmpty,
                              let searchError = networkManager.searchErrorMessage,
                              !searchError.isEmpty {
                        Text(searchError)
                            .font(.irisCaption)
                            .foregroundStyle(IrisPalette.flame)
                            .frame(maxWidth: contentMaxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sidePadding)
                            .padding(.bottom, 8)
                    }

                    if !featuredExperiments.isEmpty {
                        SectionHeader(label: experimentSectionTitle, count: experimentSectionCount, color: IrisPalette.flame)

                        VStack(spacing: 12) {
                            ForEach(Array(featuredExperiments.enumerated()), id: \.element.id) { index, experiment in
                                ExperimentCard(experiment: experiment, isDark: index == 0, language: session.selectedLanguage, onStart: { onStartExperiment(experiment) })
                            }
                        }
                        .frame(maxWidth: contentMaxWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, sidePadding)
                        .padding(.bottom, 22)
                    } else if !trimmedSearch.isEmpty, uploadedExperiments.isEmpty, !networkManager.isSearching {
                        EmptyStateCard(title: session.t("No matches found"), message: session.t("Try another search term or check that your bundled Gemini key is configured in Xcode."))
                            .frame(maxWidth: contentMaxWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sidePadding)
                            .padding(.bottom, 22)
                    }

                    SectionHeader(label: session.t("Your experiments"), count: "\(uploadedExperiments.count)")

                    if uploadedExperiments.isEmpty {
                        EmptyStateCard(title: session.t("No experiments yet"), message: session.t("Import a procedure to create your first lab flow."))
                            .frame(maxWidth: contentMaxWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sidePadding)
                            .padding(.bottom, 152)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(uploadedExperiments) { experiment in
                                ExperimentCard(experiment: experiment, isDark: false, language: session.selectedLanguage, onStart: { onStartExperiment(experiment) })
                            }
                        }
                        .frame(maxWidth: contentMaxWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, sidePadding)
                        .padding(.bottom, 152)
                    }
                }
                .frame(width: proxy.size.width, alignment: .top)
            }
            .ignoresSafeArea(edges: .top)
            .onChange(of: search) { _, newValue in
                session.updateSearchQuery(newValue)
            }
        }
    }

    private var labHeroBackground: some View {
        ZStack {
            Image("Home​Hero")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    IrisPalette.tealInk.opacity(0.28),
                    IrisPalette.tealInk.opacity(0.42),
                    IrisPalette.tealInk.opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [IrisPalette.flame.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: 220
            )

            RadialGradient(
                colors: [IrisPalette.coolAqua.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 240
            )
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.18), .clear, .black.opacity(0.32)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct SubjectImageCard: View {
    let subject: Subject
    let cardWidth: CGFloat
    @AppStorage("iris.settings.language") private var languageRawValue = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
    }

    private var imageName: String {
        switch subject {
        case .chemistry:
            return "chem"
        case .biology:
            return "bio"
        case .physics:
            return "physics"
        default:
            return "Home​Hero"
        }
    }

    private var accentColor: Color {
        switch subject {
        case .chemistry:
            return IrisPalette.flame.opacity(0.34)
        case .biology:
            return Color.green.opacity(0.34)
        case .physics:
            return IrisPalette.coolAqua.opacity(0.34)
        case .engineering:
            return Color.cyan.opacity(0.32)
        case .medicine:
            return Color.red.opacity(0.28)
        case .environmental:
            return Color.mint.opacity(0.3)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [
                        accentColor,
                        IrisPalette.tealInk.opacity(0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    HStack {
                        Spacer()

                        Text("\(subject.count)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(IrisPalette.flame)
                    }

                    Spacer()
                }
                .padding(14)
            }
            .frame(width: cardWidth, height: 86)

            VStack(spacing: 4) {
                Text(subject.localizedName(language))
                    .font(.irisBody)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: cardWidth)
            .frame(minHeight: 38)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(IrisPalette.tealInk)
        }
        .frame(width: cardWidth)
        .frame(minHeight: 124)
        .background(IrisPalette.tealInk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(IrisPalette.tealInk.opacity(0.08), lineWidth: 1)
        }
    }
}

struct ExperimentSetupScreen: View {
    let experiment: Experiment
    @ObservedObject var session: AppSession
    let onBack: () -> Void
    let onStart: () -> Void

    @State private var phoneSide = "Rear"

    private var actionLabel: String {
        session.t(session.isSessionPaused ? "CONTINUE LAB" : "START LAB")
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        NavBar(
                            title: experiment.localizedName(session.selectedLanguage),
                            onBack: onBack,
                            foreground: .white,
                            compact: true,
                            rightElement: AnyView(
                                Text(experiment.subject.localizedName(session.selectedLanguage))
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
                        SectionHeader(label: session.t("Camera"), color: IrisPalette.flame)

                        ConnectionStatusRow(statuses: [
                            .init(label: session.t("Camera"), value: cameraStatusValue, color: IrisPalette.viridian),
                            .init(label: session.t("Mode"), value: session.t(session.selectedCameraMode.rawValue), color: IrisPalette.flame),
                            .init(label: session.t("Lens"), value: session.selectedCameraMode == .phone ? session.t(phoneSide) : session.t("Remote"), color: IrisPalette.coolAqua)
                        ])
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)

                        Group {
                            if session.selectedCameraMode == .phone {
                                ZStack {
                                    CameraPreviewView(session: session.cameraManager.session)

                                    if session.cameraManager.authorizationStatus != .authorized || !session.cameraManager.isSessionRunning {
                                        previewOverlay(
                                            icon: session.cameraManager.authorizationStatus == .denied ? "camera.slash.fill" : "camera.fill",
                                            title: session.t(session.cameraManager.authorizationStatus == .denied ? "Camera access blocked" : "Preparing camera"),
                                            subtitle: session.cameraManager.errorMessage ?? session.t("IRIS is requesting camera access and starting the live preview.")
                                        )
                                    }
                                }
                            } else {
                                previewOverlay(
                                    icon: "eyeglasses",
                                    title: session.t("Glasses mode"),
                                    subtitle: session.t("IRIS will use the phone camera in the background while keeping the preview hidden.")
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
                            setupCameraCard(title: session.t("Phone"), subtitle: session.t("Device camera"), icon: "iphone", selected: session.selectedCameraMode == .phone) {
                                session.prepareCamera(position: phoneSide == "Front" ? .front : .back)
                            }

                            setupCameraCard(title: session.t("Glasses"), subtitle: session.t("External stream"), icon: "eyeglasses", selected: session.selectedCameraMode == .glasses) {
                                session.useExternalCameraSource()
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 22)

                        if session.selectedCameraMode == .phone {
                            HStack(spacing: 8) {
                                ForEach(["Front", "Rear"], id: \.self) { side in
                                    Button {
                                        phoneSide = side
                                        session.prepareCamera(position: side == "Front" ? .front : .back)
                                    } label: {
                                        Text(session.t(side).uppercased())
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

                        SectionHeader(label: session.t("Procedure"))

                        VStack(spacing: 18) {
                            ForEach(Array(experiment.localizedSteps(session.selectedLanguage).enumerated()), id: \.offset) { index, step in
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

                        SectionHeader(label: session.t("Materials"))

                        FlowLayout(experiment.localizedMaterials(session.selectedLanguage), spacing: 10) { material in
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
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                Button(action: {
                    if session.isSessionPaused {
                        session.resumePausedSession()
                    } else {
                        onStart()
                    }
                }) {
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

                Text(session.t(actionLabel))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(IrisPalette.flame)
            }
            .padding(.bottom, 96)
        }
        .task {
            guard !session.isSessionPaused else { return }
            if session.selectedCameraMode == .phone {
                session.prepareCamera(position: phoneSide == "Front" ? .front : .back)
            } else {
                session.useExternalCameraSource()
            }
        }
    }

    private var cameraStatusValue: String {
        if session.selectedCameraMode == .glasses {
            return session.cameraManager.isSessionRunning ? "Connected" : "Starting"
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
