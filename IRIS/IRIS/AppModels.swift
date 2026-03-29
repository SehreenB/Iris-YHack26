//
//  AppModels.swift
//  IRIS
//

import SwiftUI

enum Screen: String {
    case landing
    case onboarding
    case home
    case experiment
    case assistant
    case report
    case settings
}

enum Subject: String, CaseIterable, Identifiable, Codable {
    case chemistry = "Chemistry"
    case biology = "Biology"
    case physics = "Physics"
    case engineering = "Engineering"
    case medicine = "Medicine"
    case environmental = "Environmental"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chemistry: return "flask.fill"
        case .biology: return "eye.fill"
        case .physics: return "waveform.path.ecg"
        case .engineering: return "slider.horizontal.3"
        case .medicine: return "cross.case.fill"
        case .environmental: return "globe.americas.fill"
        }
    }

    var count: Int {
        switch self {
        case .chemistry: return 24
        case .biology: return 18
        case .physics: return 12
        case .engineering: return 9
        case .medicine: return 15
        case .environmental: return 7
        }
    }
}

enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var id: String { rawValue }
}

struct Experiment: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var subject: Subject
    var difficulty: Difficulty
    var time: String
    var description: String
    var steps: [String]
    var materials: [String]
    var isUploaded = false
    var createdAt = Date()

    var backendType: String {
        let normalizedName = name.lowercased()
        if normalizedName.contains("titration") {
            return "titration"
        }
        if normalizedName.contains("dna") {
            return "dna_extraction"
        }
        if normalizedName.contains("circuit") {
            return "circuit_analysis"
        }
        return subject.rawValue.lowercased()
    }

    static let demoExperiments: [Experiment] = [
        Experiment(
            name: "Acid-base titration",
            subject: .chemistry,
            difficulty: .beginner,
            time: "20 min",
            description: "Determine the concentration of an unknown acid using a standard base solution.",
            steps: [
                "Pour liquid from flask A into the beaker",
                "Add exactly 3 drops of indicator solution",
                "Slowly add liquid from flask B until colour change"
            ],
            materials: ["Flask A", "Flask B", "Beaker", "Indicator solution", "Dropper"]
        ),
        Experiment(
            name: "DNA Extraction",
            subject: .biology,
            difficulty: .intermediate,
            time: "45 min",
            description: "Extract genomic DNA from strawberry tissue using household chemicals.",
            steps: [
                "Macerate strawberries in a plastic bag",
                "Add extraction buffer and mix gently",
                "Filter the mixture into a test tube",
                "Layer cold ethanol on top to precipitate DNA"
            ],
            materials: ["Strawberries", "Dish soap", "Salt", "Ethanol", "Test tube", "Filter"]
        ),
        Experiment(
            name: "Circuit Analysis",
            subject: .physics,
            difficulty: .advanced,
            time: "60 min",
            description: "Measure voltage drops and current in a complex series-parallel circuit.",
            steps: [
                "Assemble the circuit as shown in the diagram",
                "Calibrate the digital multimeter",
                "Measure voltage across each resistor",
                "Calculate total power dissipation"
            ],
            materials: ["Resistors", "Breadboard", "Power supply", "Multimeter", "Jumper wires"]
        ),
        Experiment(
            name: "My titration protocol.pdf",
            subject: .chemistry,
            difficulty: .beginner,
            time: "15 min",
            description: "Personal lab procedure for standard titration.",
            steps: [
                "Rinse burette with distilled water",
                "Fill with titrant",
                "Perform initial reading"
            ],
            materials: ["Burette", "Titrant", "Erlenmeyer flask"],
            isUploaded: true
        )
    ]
}

enum AppMode {
    case demo
    case live
}

enum ReportBuildStatus {
    case building
    case complete
}

enum GuidanceStatus {
    case watching
    case error
}

enum CameraCaptureMode: String {
    case phone = "Phone"
    case glasses = "Glasses"
}

struct GuidanceItem: Identifiable, Hashable {
    let id = UUID()
    let type: GuidanceRowType
    let message: String
    let timestamp: Date = .now
}

struct ConnectionStatus: Hashable {
    let label: String
    let value: String
    let color: Color
}

struct LabReport: Hashable {
    var procedure: [String]
    var observations: String
    var errors: [String]
    var findings: [String]
    var suggestions: [String]
}

enum IrisPalette {
    static let tealInk = Color(red: 10 / 255, green: 36 / 255, blue: 32 / 255)
    static let viridian = Color(red: 42 / 255, green: 140 / 255, blue: 128 / 255)
    static let coolAqua = Color(red: 86 / 255, green: 191 / 255, blue: 179 / 255)
    static let paleTeal = Color(red: 168 / 255, green: 216 / 255, blue: 208 / 255)
    static let mintMist = Color(red: 212 / 255, green: 238 / 255, blue: 234 / 255)
    static let cleanWhite = Color(red: 242 / 255, green: 248 / 255, blue: 247 / 255)
    static let flame = Color(red: 232 / 255, green: 98 / 255, blue: 74 / 255)
    static let peach = Color(red: 245 / 255, green: 165 / 255, blue: 140 / 255)
    static let warmBlush = Color(red: 253 / 255, green: 238 / 255, blue: 233 / 255)
}

struct OnboardingSlide {
    let title: String
    let description: String
    let icon: String
    let tint: Color
}
