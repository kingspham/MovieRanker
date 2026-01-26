// ThemeManager.swift
// Manages app theme preferences (light/dark/system)

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("appTheme") private var storedTheme: String = AppTheme.system.rawValue

    var currentTheme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .system }
        set {
            storedTheme = newValue.rawValue
            objectWillChange.send()
        }
    }

    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }

    private init() {}
}

// MARK: - Theme-Aware Colors
extension Color {
    static var adaptiveBackground: Color {
        Color(uiColor: .systemBackground)
    }

    static var adaptiveSecondaryBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    static var adaptiveGroupedBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    static var adaptiveLabel: Color {
        Color(uiColor: .label)
    }

    static var adaptiveSecondaryLabel: Color {
        Color(uiColor: .secondaryLabel)
    }
}
