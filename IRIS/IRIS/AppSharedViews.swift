//
//  AppSharedViews.swift
//  IRIS
//

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}

struct UploadMethodCard: View {
    let selected: Bool
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(IrisPalette.mintMist)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: icon)
                            .foregroundStyle(IrisPalette.viridian)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(IrisPalette.paleTeal)
            }
            .padding(14)
            .background(selected ? IrisPalette.warmBlush : .white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? IrisPalette.flame : IrisPalette.paleTeal, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NavBar: View {
    var title: String = ""
    var label: String?
    var onBack: (() -> Void)?
    var foreground: Color = IrisPalette.tealInk
    var compact = false
    var rightElement: AnyView?
    var isHome = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(foreground)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.03), in: Circle())
                        }
                    }

                    if isHome {
                        IrisLogo(markSize: 26, titleSize: 28, lightStyle: false)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            if let label {
                                Text(label)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1.3)
                                    .foregroundStyle(IrisPalette.viridian.opacity(0.88))
                            }

                            Text(title)
                                .font(.system(size: compact ? 22 : 26, weight: .medium, design: .serif))
                                .foregroundStyle(foreground)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()

                if let rightElement {
                    rightElement
                }
            }

            if isHome {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What are we experimenting today?")
                        .font(.system(size: 30, weight: .medium, design: .serif))
                        .foregroundStyle(IrisPalette.tealInk)
                    Text("Search or bring your own procedure")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.viridian)
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, compact ? 12 : 18)
        .padding(.bottom, compact ? 6 : 14)
    }
}

struct IrisLogo: View {
    let markSize: CGFloat
    let titleSize: CGFloat
    let lightStyle: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(lightStyle ? IrisPalette.viridian.opacity(0.8) : IrisPalette.viridian, lineWidth: 2.4)
                .frame(width: markSize, height: markSize)
                .overlay {
                    Circle()
                        .fill(IrisPalette.flame)
                        .frame(width: markSize * 0.28, height: markSize * 0.28)
                }

            Text("IRIS")
                .font(.system(size: titleSize, weight: .medium, design: .serif))
                .tracking(2)
                .foregroundStyle(lightStyle ? Color.white : IrisPalette.tealInk)
        }
    }
}

struct SectionHeader: View {
    let label: String
    var count: String?
    var color: Color = IrisPalette.viridian
    var compact = false

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(color)

            Spacer()

            if let count {
                Text(count)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(IrisPalette.tealInk.opacity(0.45))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 10 : 14)
    }
}

struct ExperimentCard: View {
    let experiment: Experiment
    let isDark: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(experiment.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(isDark ? .white : IrisPalette.tealInk)

                    Text(experiment.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isDark ? IrisPalette.coolAqua : IrisPalette.tealInk.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                Text(experiment.difficulty.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isDark ? IrisPalette.coolAqua : IrisPalette.viridian)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isDark ? IrisPalette.viridian.opacity(0.2) : IrisPalette.mintMist), in: Capsule())
            }

            HStack {
                Label(experiment.time, systemImage: "clock")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isDark ? IrisPalette.coolAqua : IrisPalette.tealInk.opacity(0.55))

                Spacer()

                Button(action: onStart) {
                    HStack(spacing: 4) {
                        Text("Start")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(IrisPalette.flame)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(isDark ? 0.07 : 0))
                    .frame(height: 1)
            }
        }
        .padding(16)
        .background(isDark ? IrisPalette.tealInk : Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isDark ? IrisPalette.tealInk : IrisPalette.paleTeal.opacity(0.9), lineWidth: 1)
        }
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(IrisPalette.tealInk)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(IrisPalette.paleTeal.opacity(0.7), lineWidth: 1)
        }
    }
}

struct GuidanceRow: View {
    let type: GuidanceRowType
    let message: String
    let time: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(type.background)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: type.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(type.foreground)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(IrisPalette.tealInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(time) ago")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(IrisPalette.viridian.opacity(0.65))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().overlay(IrisPalette.paleTeal.opacity(0.4))
                .padding(.leading, 58)
        }
    }
}

struct ConnectionStatusRow: View {
    let statuses: [ConnectionStatus]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { _, status in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 7, height: 7)
                        Text(status.label)
                            .foregroundStyle(IrisPalette.tealInk.opacity(0.55))
                        Text(status.value)
                            .foregroundStyle(status.color)
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.92), in: Capsule())
                }
            }
        }
    }
}

enum GuidanceRowType {
    case confirmed
    case warning
    case qa

    var icon: String {
        switch self {
        case .confirmed: return "checkmark"
        case .warning: return "exclamationmark.triangle.fill"
        case .qa: return "message.fill"
        }
    }

    var background: Color {
        switch self {
        case .confirmed: return IrisPalette.viridian.opacity(0.12)
        case .warning: return IrisPalette.flame.opacity(0.12)
        case .qa: return IrisPalette.coolAqua.opacity(0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .confirmed: return IrisPalette.viridian
        case .warning: return IrisPalette.flame
        case .qa: return IrisPalette.coolAqua
        }
    }
}

struct ReportSection<Content: View>: View {
    let title: String
    let accent: Color
    let background: Color
    var titleColor: Color = IrisPalette.viridian
    var updated: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(titleColor)

                Spacer()

                if let updated {
                    Text("Updated \(updated) ago")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.flame)
                }
            }

            content
        }
        .padding(18)
        .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 18)
        }
    }
}

struct SettingsRow: View {
    let label: String
    var value: String?
    var toggle = false
    var compact = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: compact ? 12 : 13, weight: .medium, design: .rounded))
                .foregroundStyle(IrisPalette.tealInk)

            Spacer()

            if toggle {
                Capsule()
                    .fill(IrisPalette.flame)
                    .frame(width: 34, height: 20)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .padding(.trailing, 3)
                    }
            } else if let value {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: compact ? 12 : 13, weight: .medium, design: .rounded))
                        .foregroundStyle(IrisPalette.tealInk.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(IrisPalette.paleTeal)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 12 : 14)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider().overlay(IrisPalette.mintMist)
        }
    }
}

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(_ data: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(minHeight: 10)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, spacing)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height + spacing
                        }
                        let result = width
                        if item == data.last {
                            width = 0
                        } else {
                            width -= dimension.width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == data.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}
