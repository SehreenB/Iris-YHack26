//
//  ContentView.swift
//  IRIS
//
//  Created by betul cetintas on 2026-03-28.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = AppSession()

    var body: some View {
        ZStack(alignment: .bottom) {
            IrisPalette.cleanWhite
                .ignoresSafeArea()

            if session.showSplash {
                SplashScreen()
                    .transition(.opacity)
            } else {
                ZStack {
                    switch session.activeScreen {
                    case .landing:
                        LandingScreen {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                session.activeScreen = .onboarding
                            }
                        }
                        .transition(.opacity)

                    case .onboarding:
                        OnboardingScreen(
                            step: $session.onboardingStep,
                            onComplete: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    session.activeScreen = .home
                                }
                            }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))

                    case .home:
                        HomeScreen(
                            experiments: session.experiments,
                            onStartExperiment: { experiment in
                                session.currentExperiment = experiment
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    session.activeScreen = .experiment
                                }
                            },
                            onUpload: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                    session.showUploadSheet = true
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    case .experiment:
                        if let currentExperiment = session.currentExperiment {
                            ExperimentSetupScreen(
                                experiment: currentExperiment,
                                session: session,
                                onBack: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        session.activeScreen = .home
                                    }
                                },
                                onStart: {
                                    Task {
                                        let didStart = await session.startLiveSession(for: currentExperiment)
                                        guard didStart else { return }
                                        await MainActor.run {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                session.activeScreen = .assistant
                                            }
                                        }
                                    }
                                }
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }

                    case .assistant:
                        if let currentExperiment = session.currentExperiment {
                            AssistantScreen(
                                experiment: currentExperiment,
                                session: session,
                                onEnd: {
                                    session.endLiveSession()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        session.activeScreen = .report
                                    }
                                }
                            )
                            .transition(.scale(scale: 1.02).combined(with: .opacity))
                        }

                    case .report:
                        ReportScreen(
                            session: session,
                            onBack: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    session.activeScreen = .home
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    case .settings:
                        SettingsScreen(session: session)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                if showsTabBar {
                    BottomTabBar(session: session)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if session.showUploadSheet {
                UploadSheet(
                    session: session,
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                            session.showUploadSheet = false
                        }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(5)
            }
        }
        .task {
            guard session.showSplash else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.45)) {
                session.showSplash = false
            }
        }
    }

    private var showsTabBar: Bool {
        session.activeScreen != .landing && session.activeScreen != .onboarding
    }
}

#Preview {
    ContentView()
}
