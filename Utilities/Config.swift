// Config.swift
// CORRECTED - OMDb key was wrong!

import Foundation

enum Config {
    // MARK: - API Keys
    
    // TMDb Read Access Token (v4 Bearer token)
    static var tmdbApiKey: String {
        return "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI2OTBiODg1Yjk5MTAyNjBmYjk0MWE2NzE2YTg5MGI3ZCIsIm5iZiI6MTc2MTAxMTcxNC45NjcsInN1YiI6IjY4ZjZlODAyY2NmMDliZTY4MzEwMjE1NSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.ZvaOujU01N1zDXO4WAs0WqtNiGEM0SdejzzKjvjUzjE"
    }
    
    // OMDb API Key (8 characters - for IMDb/RT/Metacritic ratings)
    static var omdbApiKey: String {
        return "c7955ee3"
    }
    
    // Supabase Configuration
    static var supabaseUrl: String {
        return "https://ztsuzhkjotmevpcctwly.supabase.co"
    }
    
    static var supabaseAnonKey: String {
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp0c3V6aGtqb3RtZXZwY2N0d2x5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjEwNzQ2NjUsImV4cCI6MjA3NjY1MDY2NX0.azByedp7ECPeOyWlrpT55xZsNcXafYEGV4J30vo7UHU"
    }
    
    // MARK: - Feature Flags
    static let enableHaptics = true
    static let showDebugInfo = false
}
