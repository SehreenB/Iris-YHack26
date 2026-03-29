//
//  AppModels.swift
//  IRIS
//

import SwiftUI
import UIKit

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

    func localizedName(_ language: AppLanguage) -> String {
        language.localized(rawValue)
    }
}

enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var id: String { rawValue }

    func localizedName(_ language: AppLanguage) -> String {
        language.localized(rawValue)
    }
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

    func localizedName(_ language: AppLanguage) -> String {
        language.localized(name)
    }

    func localizedDescription(_ language: AppLanguage) -> String {
        language.localized(description)
    }

    func localizedSteps(_ language: AppLanguage) -> [String] {
        steps.map { language.localized($0) }
    }

    func localizedMaterials(_ language: AppLanguage) -> [String] {
        materials.map { language.localized($0) }
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
            name: "Baking Soda and Vinegar Reaction",
            subject: .chemistry,
            difficulty: .beginner,
            time: "10 min",
            description: "Observe an acid-base reaction by combining baking soda and vinegar and watching the fizzing reaction.",
            steps: [
                "Place two flasks on the desk",
                "Bring the baking soda to the desk",
                "Pour baking soda into the large flask",
                "Remove the baking soda box from the desk",
                "Bring the red vinegar to the desk",
                "Pour red vinegar into the small flask",
                "Pour large flask into small flask. Watch for fizzing!",
                "Experiment complete!"
            ],
            materials: ["Large flask", "Small flask", "Baking soda", "Red vinegar"],
            isUploaded: true
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

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "English"
    case spanish = "Español"
    case french = "Français"
    case turkish = "Türkçe"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .french:
            return "fr"
        case .turkish:
            return "tr"
        }
    }

    var speechCode: String {
        switch self {
        case .english:
            return "en-US"
        case .spanish:
            return "es-ES"
        case .french:
            return "fr-FR"
        case .turkish:
            return "tr-TR"
        }
    }

    var promptName: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .turkish:
            return "Turkish"
        }
    }

    func localized(_ text: String) -> String {
        switch self {
        case .english:
            return text
        case .spanish:
            return AppTranslations.spanish[text] ?? text
        case .french:
            return AppTranslations.french[text] ?? text
        case .turkish:
            return AppTranslations.turkish[text] ?? text
        }
    }
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

enum IrisTheme {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let elevatedSurface = Color(uiColor: .tertiarySystemBackground)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
}

enum AppTranslations {
    static let spanish: [String: String] = [
        "Chemistry": "Química",
        "Biology": "Biología",
        "Physics": "Física",
        "Engineering": "Ingeniería",
        "Medicine": "Medicina",
        "Environmental": "Ambiental",
        "Beginner": "Principiante",
        "Intermediate": "Intermedio",
        "Advanced": "Avanzado",
        "Continue with Google": "Continuar con Google",
        "Signing in...": "Iniciando sesión...",
        "New here? Set up your workspace": "¿Nuevo aquí? Configura tu espacio",
        "By continuing, you agree to our Terms of Service and Privacy Policy.": "Al continuar, aceptas nuestros Términos de servicio y Política de privacidad.",
        "Real-time AI Guidance": "Guía de IA en tiempo real",
        "Smart Lab Assistant": "Asistente inteligente de laboratorio",
        "Automated Reporting": "Informes automáticos",
        "IRIS monitors your experiment through your camera, providing step-by-step guidance as you work.": "IRIS supervisa tu experimento a través de la cámara y te guía paso a paso mientras trabajas.",
        "Ask questions anytime. IRIS understands your procedure and helps you troubleshoot in real-time.": "Haz preguntas en cualquier momento. IRIS entiende tu procedimiento y te ayuda en tiempo real.",
        "Focus on the science. IRIS automatically captures data and generates a comprehensive lab report for you.": "Concéntrate en la ciencia. IRIS captura datos automáticamente y genera un informe completo.",
        "Swipe left to enter IRIS": "Desliza a la izquierda para entrar a IRIS",
        "Swipe left to continue": "Desliza a la izquierda para continuar",
        "Skip intro": "Saltar introducción",
        "Enter IRIS": "Entrar a IRIS",
        "Your real-time AI lab teaching assistant. Precision guidance for every experiment.": "Tu asistente de laboratorio con IA en tiempo real. Guía precisa para cada experimento.",
        "What are we experimenting today?": "¿Qué vamos a experimentar hoy?",
        "Search or bring your own procedure": "Busca o trae tu propio procedimiento",
        "Start": "Iniciar",
        "Updated": "Actualizado",
        "ago": "hace",
        "experiment": "experimento",
        "experiments": "experimentos",
        "Featured": "Destacados",
        "Search results": "Resultados de búsqueda",
        "LAB ASSISTANT": "ASISTENTE DE LABORATORIO",
        "What are we\nexperimenting?": "¿Qué vamos a\nexperimentar?",
        "Search experiments...": "Buscar experimentos...",
        "Bring your own procedure": "Trae tu propio procedimiento",
        "Upload, paste, or link": "Sube, pega o enlaza",
        "Subjects": "Áreas",
        "6 areas": "6 áreas",
        "Searching with Gemini…": "Buscando con Gemini…",
        "Current step": "Paso actual",
        "No matches found": "No se encontraron resultados",
        "Try another search term or check that your bundled Gemini key is configured in Xcode.": "Prueba otra búsqueda o verifica que tu clave de Gemini esté configurada en Xcode.",
        "No experiments yet": "Aún no hay experimentos",
        "Import a procedure to create your first lab flow.": "Importa un procedimiento para crear tu primer flujo de laboratorio.",
        "Your experiments": "Tus experimentos",
        "START LAB": "INICIAR LAB",
        "CONTINUE LAB": "CONTINUAR LAB",
        "Settings": "Ajustes",
        "Demo": "Demo",
        "Live": "En vivo",
        "Runtime": "Modo",
        "Appearance": "Apariencia",
        "Language": "Idioma",
        "Account": "Cuenta",
        "Sign out": "Cerrar sesión",
        "Camera": "Cámara",
        "Mode": "Modo",
        "Lens": "Lente",
        "Remote": "Remoto",
        "Camera access blocked": "Acceso a la cámara bloqueado",
        "Preparing camera": "Preparando cámara",
        "IRIS is requesting camera access and starting the live preview.": "IRIS está solicitando acceso a la cámara e iniciando la vista previa en vivo.",
        "Waiting for glasses stream": "Esperando la transmisión de las gafas",
        "Connect the external camera feed from your ESP32 or relay backend before starting.": "Conecta la cámara externa desde tu ESP32 o backend relay antes de comenzar.",
        "Phone": "Teléfono",
        "Device camera": "Cámara del dispositivo",
        "Glasses": "Gafas",
        "External stream": "Transmisión externa",
        "Front": "Frontal",
        "Rear": "Trasera",
        "Glasses Backend": "Backend de gafas",
        "Data": "Datos",
        "Choose how IRIS runs during the experiment.": "Elige cómo funciona IRIS durante el experimento.",
        "Demo mode stays self-contained for judging.": "El modo demo se mantiene local para la evaluación.",
        "Live mode uses Sehreen's backend only for smart-glasses sessions.": "El modo en vivo usa el backend de Sehreen solo con las gafas.",
        "UI shell, phone-mode Gemini responses, and spoken guidance follow this language.": "La interfaz, las respuestas Gemini del teléfono y la voz usan este idioma.",
        "Used only when IRIS is running with the smart-glasses stream.": "Se usa solo cuando IRIS funciona con la transmisión de las gafas.",
        "Testing...": "Probando...",
        "Test connection": "Probar conexión",
        "Connected to Sehreen's backend.": "Conectado al backend de Sehreen.",
        "Lab session": "Sesión de laboratorio",
        "Reset imported procedures and local session history.": "Reinicia procedimientos importados y el historial local.",
        "Clear experiment history": "Borrar historial de experimentos",
        "HOLD TO SPEAK": "MANTÉN PARA HABLAR",
        "SAY HEY IRIS OR HOLD TO SPEAK": "DI HEY IRIS O MANTÉN PARA HABLAR",
        "LISTENING": "ESCUCHANDO",
        "Set up experiment": "Configurar experimento",
        "Correction needed": "Se necesita corrección",
        "Home": "Inicio",
        "Lab": "Lab",
        "Assistant": "Asistente",
        "Report": "Informe",
        "Acid-base titration": "Valoración ácido-base",
        "Determine the concentration of an unknown acid using a standard base solution.": "Determina la concentración de un ácido desconocido usando una base estándar.",
        "Pour liquid from flask A into the beaker": "Vierte el líquido del matraz A en el vaso",
        "Add exactly 3 drops of indicator solution": "Añade exactamente 3 gotas de indicador",
        "Slowly add liquid from flask B until colour change": "Añade lentamente líquido del matraz B hasta el cambio de color",
        "Flask A": "Matraz A",
        "Flask B": "Matraz B",
        "Beaker": "Vaso de precipitados",
        "Indicator solution": "Solución indicadora",
        "Dropper": "Gotero",
        "DNA Extraction": "Extracción de ADN",
        "Extract genomic DNA from strawberry tissue using household chemicals.": "Extrae ADN genómico de tejido de fresa usando químicos domésticos.",
        "Macerate strawberries in a plastic bag": "Machaca las fresas en una bolsa plástica",
        "Add extraction buffer and mix gently": "Añade el tampón de extracción y mezcla suavemente",
        "Filter the mixture into a test tube": "Filtra la mezcla en un tubo de ensayo",
        "Layer cold ethanol on top to precipitate DNA": "Añade etanol frío encima para precipitar el ADN",
        "Strawberries": "Fresas",
        "Dish soap": "Jabón para platos",
        "Salt": "Sal",
        "Ethanol": "Etanol",
        "Test tube": "Tubo de ensayo",
        "Filter": "Filtro",
        "Circuit Analysis": "Análisis de circuitos",
        "Measure voltage drops and current in a complex series-parallel circuit.": "Mide caídas de voltaje y corriente en un circuito serie-paralelo complejo.",
        "Assemble the circuit as shown in the diagram": "Monta el circuito como se muestra en el diagrama",
        "Calibrate the digital multimeter": "Calibra el multímetro digital",
        "Measure voltage across each resistor": "Mide el voltaje en cada resistor",
        "Calculate total power dissipation": "Calcula la disipación total de potencia",
        "Resistors": "Resistores",
        "Breadboard": "Protoboard",
        "Power supply": "Fuente de alimentación",
        "Multimeter": "Multímetro",
        "Jumper wires": "Cables puente",
        "Baking Soda and Vinegar Reaction": "Reacción de bicarbonato y vinagre",
        "Observe an acid-base reaction by combining baking soda and vinegar and watching the fizzing reaction.": "Observa una reacción ácido-base combinando bicarbonato y vinagre y viendo la efervescencia.",
        "Place two flasks on the desk": "Coloca dos matraces sobre la mesa",
        "Bring the baking soda to the desk": "Lleva el bicarbonato a la mesa",
        "Pour baking soda into the large flask": "Vierte bicarbonato en el matraz grande",
        "Remove the baking soda box from the desk": "Retira la caja de bicarbonato de la mesa",
        "Bring the red vinegar to the desk": "Lleva el vinagre rojo a la mesa",
        "Pour red vinegar into the small flask": "Vierte el vinagre rojo en el matraz pequeño",
        "Pour large flask into small flask. Watch for fizzing!": "Vierte el matraz grande en el pequeño. ¡Observa la efervescencia!",
        "Experiment complete!": "¡Experimento completo!",
        "Two flasks": "Dos matraces",
        "Baking soda": "Bicarbonato",
        "Vinegar": "Vinagre",
        "My titration protocol.pdf": "Mi protocolo de valoración.pdf",
        "Personal lab procedure for standard titration.": "Procedimiento personal de laboratorio para una valoración estándar.",
        "Rinse burette with distilled water": "Enjuaga la bureta con agua destilada",
        "Fill with titrant": "Llénala con titulante",
        "Perform initial reading": "Realiza la lectura inicial",
        "Burette": "Bureta",
        "Titrant": "Titulante",
        "Erlenmeyer flask": "Matraz Erlenmeyer",
        "Phone camera mode runs locally on-device without Sehreen's backend.": "El modo cámara del teléfono funciona localmente en el dispositivo sin el backend de Sehreen.",
        "Connected to glasses stream. Waiting for live guidance from Sehreen's backend.": "Conectado al flujo de gafas. Esperando guía en vivo desde el backend de Sehreen.",
        "Experiment flow completed. Review the report for final notes.": "El flujo del experimento se completó. Revisa el informe para las notas finales.",
        "Lab paused. Return and tap Continue lab when you're ready.": "Laboratorio en pausa. Regresa y pulsa Continuar laboratorio cuando estés listo.",
        "Lab resumed. IRIS is watching the current step again.": "Laboratorio reanudado. IRIS vuelve a observar el paso actual.",
        "I'm here. Ask me about this step.": "Aquí estoy. Pregúntame sobre este paso.",
        "No session data captured yet.": "Aún no se han capturado datos de la sesión.",
        "No observations captured yet.": "Aún no se han capturado observaciones.",
        "No confirmed steps.": "No hay pasos confirmados.",
        "None": "Ninguno",
        "Could not reach the backend.": "No se pudo alcanzar el backend.",
        "Select a file to extract its procedure text.": "Selecciona un archivo para extraer el texto del procedimiento.",
        "PDF text loaded and ready to edit.": "Texto PDF cargado y listo para editar.",
        "e.g. Acid-base titration": "p. ej. Valoración ácido-base",
        "Choose a PDF to extract its procedure text, then adjust it here if needed.": "Elige un PDF para extraer el texto del procedimiento y ajústalo aquí si hace falta.",
        "Fetch a lab page URL and the extracted procedure will appear here.": "Carga la URL de una página de laboratorio y el procedimiento extraído aparecerá aquí.",
        "Paste your lab procedure here. Include steps and, if possible, a materials line.": "Pega aquí tu procedimiento de laboratorio. Incluye los pasos y, si es posible, una línea de materiales.",
        "Import a PDF first.": "Primero importa un PDF.",
        "Add procedure text before continuing.": "Añade el texto del procedimiento antes de continuar.",
        "Could not open that PDF.": "No se pudo abrir ese PDF.",
        "Could not read that PDF.": "No se pudo leer ese PDF.",
        "That PDF did not contain readable text.": "Ese PDF no contenía texto legible.",
        "Loaded PDF text.": "Texto del PDF cargado.",
        "Enter a valid URL.": "Introduce una URL válida.",
        "Could not parse that PDF URL.": "No se pudo procesar esa URL de PDF.",
        "Could not read text from that URL.": "No se pudo leer texto desde esa URL.",
        "That URL did not contain readable procedure text.": "Esa URL no contenía texto legible del procedimiento.",
        "Loaded procedure from URL.": "Procedimiento cargado desde URL.",
        "Could not fetch that URL.": "No se pudo cargar esa URL."
    ]

    static let french: [String: String] = [
        "Chemistry": "Chimie",
        "Biology": "Biologie",
        "Physics": "Physique",
        "Engineering": "Ingénierie",
        "Medicine": "Médecine",
        "Environmental": "Environnement",
        "Beginner": "Débutant",
        "Intermediate": "Intermédiaire",
        "Advanced": "Avancé",
        "Continue with Google": "Continuer avec Google",
        "Signing in...": "Connexion...",
        "New here? Set up your workspace": "Nouveau ? Configurez votre espace",
        "By continuing, you agree to our Terms of Service and Privacy Policy.": "En continuant, vous acceptez nos Conditions d’utilisation et notre Politique de confidentialité.",
        "Real-time AI Guidance": "Guidage IA en temps réel",
        "Smart Lab Assistant": "Assistant de labo intelligent",
        "Automated Reporting": "Rapports automatiques",
        "IRIS monitors your experiment through your camera, providing step-by-step guidance as you work.": "IRIS surveille votre expérience via la caméra et vous guide étape par étape.",
        "Ask questions anytime. IRIS understands your procedure and helps you troubleshoot in real-time.": "Posez des questions à tout moment. IRIS comprend votre procédure et vous aide en temps réel.",
        "Focus on the science. IRIS automatically captures data and generates a comprehensive lab report for you.": "Concentrez-vous sur la science. IRIS capture les données et génère un rapport complet.",
        "Swipe left to enter IRIS": "Glissez à gauche pour entrer dans IRIS",
        "Swipe left to continue": "Glissez à gauche pour continuer",
        "Skip intro": "Passer l’intro",
        "Enter IRIS": "Entrer dans IRIS",
        "Your real-time AI lab teaching assistant. Precision guidance for every experiment.": "Votre assistant de laboratoire IA en temps réel. Un guidage précis pour chaque expérience.",
        "What are we experimenting today?": "Qu’allons-nous expérimenter aujourd’hui ?",
        "Search or bring your own procedure": "Recherchez ou apportez votre propre procédure",
        "Start": "Démarrer",
        "Updated": "Mis à jour",
        "ago": "il y a",
        "experiment": "expérience",
        "experiments": "expériences",
        "Featured": "À la une",
        "Search results": "Résultats de recherche",
        "LAB ASSISTANT": "ASSISTANT DE LABO",
        "What are we\nexperimenting?": "Que sommes-nous en\ntrain d’expérimenter ?",
        "Search experiments...": "Rechercher des expériences...",
        "Bring your own procedure": "Apportez votre propre procédure",
        "Upload, paste, or link": "Importer, coller ou lier",
        "Subjects": "Sujets",
        "6 areas": "6 domaines",
        "Searching with Gemini…": "Recherche avec Gemini…",
        "Current step": "Étape actuelle",
        "No matches found": "Aucun résultat trouvé",
        "Try another search term or check that your bundled Gemini key is configured in Xcode.": "Essayez une autre recherche ou vérifiez que votre clé Gemini est configurée dans Xcode.",
        "No experiments yet": "Aucune expérience pour le moment",
        "Import a procedure to create your first lab flow.": "Importez une procédure pour créer votre premier flux de labo.",
        "Your experiments": "Vos expériences",
        "START LAB": "DÉMARRER LE LABO",
        "CONTINUE LAB": "REPRENDRE LE LABO",
        "Settings": "Réglages",
        "Demo": "Démo",
        "Live": "Direct",
        "Runtime": "Mode",
        "Appearance": "Apparence",
        "Language": "Langue",
        "Account": "Compte",
        "Sign out": "Se déconnecter",
        "Camera": "Caméra",
        "Mode": "Mode",
        "Lens": "Objectif",
        "Remote": "Distant",
        "Camera access blocked": "Accès caméra bloqué",
        "Preparing camera": "Préparation de la caméra",
        "IRIS is requesting camera access and starting the live preview.": "IRIS demande l’accès à la caméra et démarre l’aperçu en direct.",
        "Waiting for glasses stream": "En attente du flux des lunettes",
        "Connect the external camera feed from your ESP32 or relay backend before starting.": "Connectez le flux externe depuis votre ESP32 ou backend relais avant de commencer.",
        "Phone": "Téléphone",
        "Device camera": "Caméra de l’appareil",
        "Glasses": "Lunettes",
        "External stream": "Flux externe",
        "Front": "Avant",
        "Rear": "Arrière",
        "Glasses Backend": "Backend des lunettes",
        "Data": "Données",
        "Choose how IRIS runs during the experiment.": "Choisissez comment IRIS fonctionne pendant l’expérience.",
        "Demo mode stays self-contained for judging.": "Le mode démo reste local pour la présentation.",
        "Live mode uses Sehreen's backend only for smart-glasses sessions.": "Le mode direct utilise le backend de Sehreen uniquement avec les lunettes.",
        "UI shell, phone-mode Gemini responses, and spoken guidance follow this language.": "L’interface, Gemini sur téléphone et la voix suivent cette langue.",
        "Used only when IRIS is running with the smart-glasses stream.": "Utilisé seulement quand IRIS fonctionne avec le flux des lunettes.",
        "Testing...": "Test...",
        "Test connection": "Tester la connexion",
        "Connected to Sehreen's backend.": "Connecté au backend de Sehreen.",
        "Lab session": "Session de laboratoire",
        "Reset imported procedures and local session history.": "Réinitialiser les procédures importées et l’historique local.",
        "Clear experiment history": "Effacer l’historique des expériences",
        "HOLD TO SPEAK": "MAINTENIR POUR PARLER",
        "SAY HEY IRIS OR HOLD TO SPEAK": "DITES HEY IRIS OU MAINTENEZ POUR PARLER",
        "LISTENING": "ÉCOUTE",
        "Set up experiment": "Configurer l’expérience",
        "Correction needed": "Correction nécessaire",
        "Home": "Accueil",
        "Lab": "Labo",
        "Assistant": "Assistant",
        "Report": "Rapport",
        "Acid-base titration": "Titrage acido-basique",
        "Determine the concentration of an unknown acid using a standard base solution.": "Déterminez la concentration d’un acide inconnu à l’aide d’une base étalon.",
        "Pour liquid from flask A into the beaker": "Versez le liquide du flacon A dans le bécher",
        "Add exactly 3 drops of indicator solution": "Ajoutez exactement 3 gouttes d’indicateur",
        "Slowly add liquid from flask B until colour change": "Ajoutez lentement le liquide du flacon B jusqu’au changement de couleur",
        "Flask A": "Flacon A",
        "Flask B": "Flacon B",
        "Beaker": "Bécher",
        "Indicator solution": "Solution indicatrice",
        "Dropper": "Compte-gouttes",
        "DNA Extraction": "Extraction d’ADN",
        "Extract genomic DNA from strawberry tissue using household chemicals.": "Extrayez l’ADN génomique de tissu de fraise avec des produits ménagers.",
        "Macerate strawberries in a plastic bag": "Écrasez les fraises dans un sac plastique",
        "Add extraction buffer and mix gently": "Ajoutez le tampon d’extraction et mélangez doucement",
        "Filter the mixture into a test tube": "Filtrez le mélange dans un tube à essai",
        "Layer cold ethanol on top to precipitate DNA": "Ajoutez de l’éthanol froid au-dessus pour précipiter l’ADN",
        "Strawberries": "Fraises",
        "Dish soap": "Liquide vaisselle",
        "Salt": "Sel",
        "Ethanol": "Éthanol",
        "Test tube": "Tube à essai",
        "Filter": "Filtre",
        "Circuit Analysis": "Analyse de circuit",
        "Measure voltage drops and current in a complex series-parallel circuit.": "Mesurez les chutes de tension et le courant dans un circuit série-parallèle complexe.",
        "Assemble the circuit as shown in the diagram": "Assemblez le circuit comme sur le schéma",
        "Calibrate the digital multimeter": "Calibrez le multimètre numérique",
        "Measure voltage across each resistor": "Mesurez la tension aux bornes de chaque résistance",
        "Calculate total power dissipation": "Calculez la dissipation totale de puissance",
        "Resistors": "Résistances",
        "Breadboard": "Plaque d’essai",
        "Power supply": "Alimentation",
        "Multimeter": "Multimètre",
        "Jumper wires": "Fils de connexion",
        "Baking Soda and Vinegar Reaction": "Réaction bicarbonate-vinaigre",
        "Observe an acid-base reaction by combining baking soda and vinegar and watching the fizzing reaction.": "Observez une réaction acido-basique en mélangeant bicarbonate et vinaigre et en regardant l’effervescence.",
        "Place two flasks on the desk": "Placez deux flacons sur la table",
        "Bring the baking soda to the desk": "Apportez le bicarbonate sur la table",
        "Pour baking soda into the large flask": "Versez le bicarbonate dans le grand flacon",
        "Remove the baking soda box from the desk": "Retirez la boîte de bicarbonate de la table",
        "Bring the red vinegar to the desk": "Apportez le vinaigre rouge sur la table",
        "Pour red vinegar into the small flask": "Versez le vinaigre rouge dans le petit flacon",
        "Pour large flask into small flask. Watch for fizzing!": "Versez le grand flacon dans le petit. Observez l’effervescence !",
        "Experiment complete!": "Expérience terminée !",
        "Two flasks": "Deux flacons",
        "Baking soda": "Bicarbonate",
        "Vinegar": "Vinaigre",
        "My titration protocol.pdf": "Mon protocole de titrage.pdf",
        "Personal lab procedure for standard titration.": "Procédure personnelle de laboratoire pour un titrage standard.",
        "Rinse burette with distilled water": "Rincez la burette à l’eau distillée",
        "Fill with titrant": "Remplissez avec le titrant",
        "Perform initial reading": "Effectuez la lecture initiale",
        "Burette": "Burette",
        "Titrant": "Titrant",
        "Erlenmeyer flask": "Fiole Erlenmeyer",
        "Phone camera mode runs locally on-device without Sehreen's backend.": "Le mode caméra du téléphone fonctionne localement sur l’appareil sans le backend de Sehreen.",
        "Connected to glasses stream. Waiting for live guidance from Sehreen's backend.": "Connecté au flux des lunettes. En attente du guidage en direct depuis le backend de Sehreen.",
        "Experiment flow completed. Review the report for final notes.": "Le déroulé de l’expérience est terminé. Consultez le rapport pour les notes finales.",
        "Lab paused. Return and tap Continue lab when you're ready.": "Labo en pause. Revenez et touchez Continuer le labo quand vous êtes prêt.",
        "Lab resumed. IRIS is watching the current step again.": "Labo repris. IRIS observe de nouveau l’étape actuelle.",
        "I'm here. Ask me about this step.": "Je suis là. Posez-moi une question sur cette étape.",
        "No session data captured yet.": "Aucune donnée de session capturée pour le moment.",
        "No observations captured yet.": "Aucune observation capturée pour le moment.",
        "No confirmed steps.": "Aucune étape confirmée.",
        "None": "Aucun",
        "Could not reach the backend.": "Impossible d’atteindre le backend.",
        "Select a file to extract its procedure text.": "Choisissez un fichier pour extraire le texte de la procédure.",
        "PDF text loaded and ready to edit.": "Texte PDF chargé et prêt à être modifié.",
        "e.g. Acid-base titration": "ex. Titrage acido-basique",
        "Choose a PDF to extract its procedure text, then adjust it here if needed.": "Choisissez un PDF pour extraire le texte de la procédure, puis ajustez-le ici si besoin.",
        "Fetch a lab page URL and the extracted procedure will appear here.": "Récupérez l’URL d’une page de labo et la procédure extraite apparaîtra ici.",
        "Paste your lab procedure here. Include steps and, if possible, a materials line.": "Collez ici votre procédure de laboratoire. Ajoutez les étapes et si possible une ligne de matériel.",
        "Import a PDF first.": "Importez d’abord un PDF.",
        "Add procedure text before continuing.": "Ajoutez le texte de la procédure avant de continuer.",
        "Could not open that PDF.": "Impossible d’ouvrir ce PDF.",
        "Could not read that PDF.": "Impossible de lire ce PDF.",
        "That PDF did not contain readable text.": "Ce PDF ne contenait pas de texte lisible.",
        "Loaded PDF text.": "Texte PDF chargé.",
        "Enter a valid URL.": "Saisissez une URL valide.",
        "Could not parse that PDF URL.": "Impossible d’analyser cette URL PDF.",
        "Could not read text from that URL.": "Impossible de lire le texte depuis cette URL.",
        "That URL did not contain readable procedure text.": "Cette URL ne contenait pas de texte de procédure lisible.",
        "Loaded procedure from URL.": "Procédure chargée depuis l’URL.",
        "Could not fetch that URL.": "Impossible de charger cette URL."
    ]

    static let turkish: [String: String] = [
        "Chemistry": "Kimya",
        "Biology": "Biyoloji",
        "Physics": "Fizik",
        "Engineering": "Mühendislik",
        "Medicine": "Tıp",
        "Environmental": "Çevre",
        "Beginner": "Başlangıç",
        "Intermediate": "Orta",
        "Advanced": "İleri",
        "Continue with Google": "Google ile devam et",
        "Signing in...": "Giriş yapılıyor...",
        "New here? Set up your workspace": "Yeni misin? Çalışma alanını kur",
        "By continuing, you agree to our Terms of Service and Privacy Policy.": "Devam ederek Hizmet Koşulları ve Gizlilik Politikası’nı kabul etmiş olursun.",
        "Real-time AI Guidance": "Gerçek zamanlı yapay zeka rehberliği",
        "Smart Lab Assistant": "Akıllı laboratuvar asistanı",
        "Automated Reporting": "Otomatik raporlama",
        "IRIS monitors your experiment through your camera, providing step-by-step guidance as you work.": "IRIS kameran üzerinden deneyi izler ve çalışırken sana adım adım rehberlik eder.",
        "Ask questions anytime. IRIS understands your procedure and helps you troubleshoot in real-time.": "İstediğin zaman soru sor. IRIS prosedürü anlar ve gerçek zamanlı yardımcı olur.",
        "Focus on the science. IRIS automatically captures data and generates a comprehensive lab report for you.": "Bilime odaklan. IRIS verileri otomatik toplar ve kapsamlı rapor oluşturur.",
        "Swipe left to enter IRIS": "IRIS’e girmek için sola kaydır",
        "Swipe left to continue": "Devam etmek için sola kaydır",
        "Skip intro": "Tanıtımı geç",
        "Enter IRIS": "IRIS’e gir",
        "Your real-time AI lab teaching assistant. Precision guidance for every experiment.": "Gerçek zamanlı yapay zekâ laboratuvar asistanınız. Her deney için hassas yönlendirme.",
        "What are we experimenting today?": "Bugün ne deniyoruz?",
        "Search or bring your own procedure": "Ara veya kendi prosedürünü getir",
        "Start": "Başlat",
        "Updated": "Güncellendi",
        "ago": "önce",
        "experiment": "deney",
        "experiments": "deneyler",
        "Featured": "Öne çıkanlar",
        "Search results": "Arama sonuçları",
        "LAB ASSISTANT": "LAB ASİSTANI",
        "What are we\nexperimenting?": "Bugün neyin\ndeneyini yapıyoruz?",
        "Search experiments...": "Deney ara...",
        "Bring your own procedure": "Kendi prosedürünü getir",
        "Upload, paste, or link": "Yükle, yapıştır veya bağlantı ekle",
        "Subjects": "Konular",
        "6 areas": "6 alan",
        "Searching with Gemini…": "Gemini ile aranıyor…",
        "Current step": "Geçerli adım",
        "No matches found": "Eşleşme bulunamadı",
        "Try another search term or check that your bundled Gemini key is configured in Xcode.": "Başka bir arama deneyin veya Gemini anahtarınızın Xcode’da ayarlı olduğunu kontrol edin.",
        "No experiments yet": "Henüz deney yok",
        "Import a procedure to create your first lab flow.": "İlk laboratuvar akışını oluşturmak için bir prosedür içe aktarın.",
        "Your experiments": "Deneylerin",
        "START LAB": "LABI BAŞLAT",
        "CONTINUE LAB": "LABA DEVAM ET",
        "Settings": "Ayarlar",
        "Demo": "Demo",
        "Live": "Canlı",
        "Runtime": "Çalışma modu",
        "Appearance": "Görünüm",
        "Language": "Dil",
        "Account": "Hesap",
        "Sign out": "Çıkış yap",
        "Camera": "Kamera",
        "Mode": "Mod",
        "Lens": "Lens",
        "Remote": "Uzak",
        "Camera access blocked": "Kamera erişimi engellendi",
        "Preparing camera": "Kamera hazırlanıyor",
        "IRIS is requesting camera access and starting the live preview.": "IRIS kamera erişimi istiyor ve canlı önizlemeyi başlatıyor.",
        "Waiting for glasses stream": "Gözlük yayını bekleniyor",
        "Connect the external camera feed from your ESP32 or relay backend before starting.": "Başlamadan önce ESP32 veya relay backend üzerinden harici kamera akışını bağlayın.",
        "Phone": "Telefon",
        "Device camera": "Cihaz kamerası",
        "Glasses": "Gözlük",
        "External stream": "Harici yayın",
        "Front": "Ön",
        "Rear": "Arka",
        "Glasses Backend": "Gözlük backend’i",
        "Data": "Veriler",
        "Choose how IRIS runs during the experiment.": "IRIS’in deney sırasında nasıl çalışacağını seç.",
        "Demo mode stays self-contained for judging.": "Demo modu jüri için yerel kalır.",
        "Live mode uses Sehreen's backend only for smart-glasses sessions.": "Canlı mod Sehreen’in backend’ini sadece akıllı gözlük oturumlarında kullanır.",
        "UI shell, phone-mode Gemini responses, and spoken guidance follow this language.": "Arayüz, telefon Gemini yanıtları ve sesli rehber bu dili kullanır.",
        "Used only when IRIS is running with the smart-glasses stream.": "Sadece IRIS akıllı gözlük akışıyla çalışırken kullanılır.",
        "Testing...": "Test ediliyor...",
        "Test connection": "Bağlantıyı test et",
        "Connected to Sehreen's backend.": "Sehreen’in backend’ine bağlandı.",
        "Lab session": "Laboratuvar oturumu",
        "Reset imported procedures and local session history.": "İçe aktarılan prosedürleri ve yerel geçmişi sıfırla.",
        "Clear experiment history": "Deney geçmişini temizle",
        "HOLD TO SPEAK": "KONUŞMAK İÇİN BASILI TUT",
        "SAY HEY IRIS OR HOLD TO SPEAK": "HEY IRIS DE YA DA BASILI TUT",
        "LISTENING": "DİNLİYOR",
        "Set up experiment": "Deneyi ayarla",
        "Correction needed": "Düzeltme gerekli",
        "Home": "Ana sayfa",
        "Lab": "Lab",
        "Assistant": "Asistan",
        "Report": "Rapor",
        "Acid-base titration": "Asit-baz titrasyonu",
        "Determine the concentration of an unknown acid using a standard base solution.": "Standart bir baz çözeltisi kullanarak bilinmeyen bir asidin derişimini belirleyin.",
        "Pour liquid from flask A into the beaker": "A balonundaki sıvıyı behere dökün",
        "Add exactly 3 drops of indicator solution": "Tam olarak 3 damla indikatör çözeltisi ekleyin",
        "Slowly add liquid from flask B until colour change": "Renk değişene kadar B balonundaki sıvıyı yavaşça ekleyin",
        "Flask A": "Balon A",
        "Flask B": "Balon B",
        "Beaker": "Beher",
        "Indicator solution": "İndikatör çözeltisi",
        "Dropper": "Damlalık",
        "DNA Extraction": "DNA Ekstraksiyonu",
        "Extract genomic DNA from strawberry tissue using household chemicals.": "Ev tipi kimyasallarla çilek dokusundan genomik DNA çıkarın.",
        "Macerate strawberries in a plastic bag": "Çilekleri plastik poşette ezin",
        "Add extraction buffer and mix gently": "Ekstraksiyon tamponu ekleyip nazikçe karıştırın",
        "Filter the mixture into a test tube": "Karışımı bir deney tüpüne süzün",
        "Layer cold ethanol on top to precipitate DNA": "DNA’yı çöktürmek için üste soğuk etanol ekleyin",
        "Strawberries": "Çilek",
        "Dish soap": "Bulaşık deterjanı",
        "Salt": "Tuz",
        "Ethanol": "Etanol",
        "Test tube": "Deney tüpü",
        "Filter": "Filtre",
        "Circuit Analysis": "Devre Analizi",
        "Measure voltage drops and current in a complex series-parallel circuit.": "Karma bir seri-paralel devrede gerilim düşümlerini ve akımı ölçün.",
        "Assemble the circuit as shown in the diagram": "Devreyi şemadaki gibi kurun",
        "Calibrate the digital multimeter": "Dijital multimetreyi kalibre edin",
        "Measure voltage across each resistor": "Her direnç üzerindeki gerilimi ölçün",
        "Calculate total power dissipation": "Toplam güç kaybını hesaplayın",
        "Resistors": "Dirençler",
        "Breadboard": "Breadboard",
        "Power supply": "Güç kaynağı",
        "Multimeter": "Multimetre",
        "Jumper wires": "Bağlantı kabloları",
        "Baking Soda and Vinegar Reaction": "Karbonat ve Sirke Tepkimesi",
        "Observe an acid-base reaction by combining baking soda and vinegar and watching the fizzing reaction.": "Karbonat ve sirkeyi birleştirip köpürmeyi gözlemleyerek bir asit-baz tepkimesini inceleyin.",
        "Place two flasks on the desk": "Masaya iki balon yerleştirin",
        "Bring the baking soda to the desk": "Karbonatı masaya getirin",
        "Pour baking soda into the large flask": "Karbonatı büyük şişeye dökün",
        "Remove the baking soda box from the desk": "Karbonat kutusunu masadan kaldırın",
        "Bring the red vinegar to the desk": "Kırmızı sirkeyi masaya getirin",
        "Pour red vinegar into the small flask": "Kırmızı sirkeyi küçük şişeye dökün",
        "Pour large flask into small flask. Watch for fizzing!": "Büyük şişeyi küçük şişeye dökün. Köpürmeyi izleyin!",
        "Experiment complete!": "Deney tamamlandı!",
        "Two flasks": "İki balon",
        "Baking soda": "Karbonat",
        "Vinegar": "Sirke",
        "My titration protocol.pdf": "Titrasyon protokolüm.pdf",
        "Personal lab procedure for standard titration.": "Standart titrasyon için kişisel laboratuvar prosedürü.",
        "Rinse burette with distilled water": "Büretı saf suyla durulayın",
        "Fill with titrant": "Titrant ile doldurun",
        "Perform initial reading": "İlk okumayı yapın",
        "Burette": "Büret",
        "Titrant": "Titrant",
        "Erlenmeyer flask": "Erlenmayer balonu",
        "Phone camera mode runs locally on-device without Sehreen's backend.": "Telefon kamerası modu Sehreen'in backend’i olmadan cihazda yerel çalışır.",
        "Loaded %d steps from Sehreen's backend.": "Sehreen'in backend’inden %d adım yüklendi.",
        "Connected to glasses stream. Waiting for live guidance from Sehreen's backend.": "Gözlük akışına bağlandı. Sehreen'in backend’inden canlı yönlendirme bekleniyor.",
        "Completed step %d: %@": "%d. adım tamamlandı: %@",
        "Experiment flow completed. Review the report for final notes.": "Deney akışı tamamlandı. Son notlar için raporu inceleyin.",
        "Lab paused. Return and tap Continue lab when you're ready.": "Laboratuvar duraklatıldı. Hazır olduğunuzda dönüp Laboratuvara devam et’e dokunun.",
        "Lab resumed. IRIS is watching the current step again.": "Laboratuvar devam etti. IRIS mevcut adımı yeniden izliyor.",
        "I'm here. Ask me about this step.": "Buradayım. Bu adım hakkında bana soru sor.",
        "No session data captured yet.": "Henüz oturum verisi yakalanmadı.",
        "No observations captured yet.": "Henüz gözlem kaydedilmedi.",
        "No confirmed steps.": "Henüz onaylanmış adım yok.",
        "None": "Yok",
        "Could not reach the backend.": "Backend’e ulaşılamadı.",
        "Select a file to extract its procedure text.": "Prosedür metnini çıkarmak için bir dosya seçin.",
        "PDF text loaded and ready to edit.": "PDF metni yüklendi ve düzenlemeye hazır.",
        "e.g. Acid-base titration": "örn. Asit-baz titrasyonu",
        "Choose a PDF to extract its procedure text, then adjust it here if needed.": "Prosedür metnini çıkarmak için bir PDF seçin, gerekirse burada düzenleyin.",
        "Fetch a lab page URL and the extracted procedure will appear here.": "Bir laboratuvar sayfası URL’si alın ve çıkarılan prosedür burada görünsün.",
        "Paste your lab procedure here. Include steps and, if possible, a materials line.": "Laboratuvar prosedürünü buraya yapıştırın. Adımları ve mümkünse malzeme satırını ekleyin.",
        "Import a PDF first.": "Önce bir PDF içe aktarın.",
        "Add procedure text before continuing.": "Devam etmeden önce prosedür metni ekleyin.",
        "Could not open that PDF.": "Bu PDF açılamadı.",
        "Could not read that PDF.": "Bu PDF okunamadı.",
        "That PDF did not contain readable text.": "Bu PDF okunabilir metin içermiyordu.",
        "Loaded PDF text.": "PDF metni yüklendi.",
        "Enter a valid URL.": "Geçerli bir URL girin.",
        "Could not parse that PDF URL.": "Bu PDF URL’si işlenemedi.",
        "Could not read text from that URL.": "Bu URL’den metin okunamadı.",
        "That URL did not contain readable procedure text.": "Bu URL okunabilir prosedür metni içermiyordu.",
        "Loaded procedure from URL.": "Prosedür URL’den yüklendi.",
        "Could not fetch that URL.": "Bu URL getirilemedi."
    ]
}

struct OnboardingSlide {
    let title: String
    let description: String
    let icon: String
    let tint: Color
}
