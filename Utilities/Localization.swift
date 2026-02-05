// Localization.swift
// Runtime language switching for English and Spanish

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        }
    }

    /// TMDb API language code (e.g. "en-US", "es-ES")
    var tmdbLanguage: String {
        switch self {
        case .english: return "en-US"
        case .spanish: return "es-ES"
        }
    }

    /// TMDb API region code
    var tmdbRegion: String {
        switch self {
        case .english: return "US"
        case .spanish: return "ES"
        }
    }
}

/// Lightweight localization helper. Reads the user's language preference from UserDefaults.
/// Usage: `L10n.explore`, `L10n.savedItems`, etc.
struct L10n {
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .english
    }

    static var isSpanish: Bool { current == .spanish }

    // MARK: - Tab Bar
    static var activity: String { isSpanish ? "Actividad" : "Activity" }
    static var explore: String { isSpanish ? "Explorar" : "Explore" }
    static var rankings: String { isSpanish ? "Clasificación" : "Rankings" }
    static var library: String { isSpanish ? "Biblioteca" : "Library" }
    static var profile: String { isSpanish ? "Perfil" : "Profile" }

    // MARK: - Explore / Search
    static var suggestedMovies: String { isSpanish ? "Películas Sugeridas" : "Suggested Movies" }
    static var suggestedShows: String { isSpanish ? "Series Sugeridas" : "Suggested Shows" }
    static var trendingToday: String { isSpanish ? "Tendencias Hoy" : "Trending Today" }
    static var inTheaters: String { isSpanish ? "En Cartelera" : "In Theaters" }
    static var streamingNow: String { isSpanish ? "En Streaming" : "Streaming Now" }
    static var popularBooks: String { isSpanish ? "Libros Populares" : "Popular Books" }
    static var topPodcasts: String { isSpanish ? "Podcasts Destacados" : "Top Podcasts" }
    static var searchPlaceholder: String { isSpanish ? "Buscar películas, series, libros..." : "Search movies, shows, books..." }
    static var noResults: String { isSpanish ? "Sin resultados" : "No Results" }
    static var didYouMean: String { isSpanish ? "¿Quisiste decir" : "Did you mean" }

    // MARK: - Library Tabs
    static var history: String { isSpanish ? "Historial" : "History" }
    static var saved: String { isSpanish ? "Guardados" : "Saved" }
    static var lists: String { isSpanish ? "Listas" : "Lists" }

    // MARK: - Saved / Watchlist
    static var noSavedItems: String { isSpanish ? "Sin Elementos Guardados" : "No Saved Items" }
    static var savedDescription: String { isSpanish ? "Los elementos que guardes aparecerán aquí" : "Items you save will appear here" }
    static var searchWatchlist: String { isSpanish ? "Buscar en lista" : "Search watchlist" }
    static var remove: String { isSpanish ? "Eliminar" : "Remove" }
    static var dateAdded: String { isSpanish ? "Fecha Agregada" : "Date Added" }
    static var predictedScore: String { isSpanish ? "Puntuación Predicha" : "Predicted Score" }
    static var title: String { isSpanish ? "Título" : "Title" }
    static var year: String { isSpanish ? "Año" : "Year" }
    static var rankAll: String { isSpanish ? "Clasificar Todos" : "Rank All" }
    static var ascending: String { isSpanish ? "Ascendente" : "Ascending" }
    static var descending: String { isSpanish ? "Descendente" : "Descending" }

    // MARK: - Rankings / Leaderboard
    static var all: String { isSpanish ? "Todos" : "All" }
    static var movies: String { isSpanish ? "Películas" : "Movies" }
    static var shows: String { isSpanish ? "Series" : "Shows" }
    static var books: String { isSpanish ? "Libros" : "Books" }
    static var podcasts: String { isSpanish ? "Podcasts" : "Podcasts" }
    static var noRankings: String { isSpanish ? "Sin Clasificaciones" : "No Rankings Yet" }
    static var rankingsDescription: String { isSpanish ? "¡Empieza a calificar películas para ver tu clasificación!" : "Start rating movies to see your rankings!" }

    // MARK: - Profile
    static var settings: String { isSpanish ? "Ajustes" : "Settings" }
    static var signOut: String { isSpanish ? "Cerrar Sesión" : "Sign Out" }
    static var badges: String { isSpanish ? "Insignias" : "Badges" }
    static var favorites: String { isSpanish ? "Favoritos" : "Favorites" }
    static var tasteProfile: String { isSpanish ? "Perfil de Gustos" : "Taste Profile" }

    // MARK: - Settings
    static var appearance: String { isSpanish ? "Apariencia" : "Appearance" }
    static var language: String { isSpanish ? "Idioma" : "Language" }
    static var languageFooter: String { isSpanish ? "Cambia el idioma de la aplicación y los resultados de búsqueda" : "Changes the app language and search results" }
    static var yourStats: String { isSpanish ? "Tus Estadísticas" : "Your Stats" }
    static var rankedItems: String { isSpanish ? "Elementos Clasificados:" : "Ranked Items:" }
    static var watchlist: String { isSpanish ? "Lista de Seguimiento:" : "Watchlist:" }
    static var logEntries: String { isSpanish ? "Entradas del Registro:" : "Log Entries:" }
    static var importData: String { isSpanish ? "Importar Datos" : "Import Data" }
    static var importWatchHistory: String { isSpanish ? "Importar Historial" : "Import Watch History" }
    static var quickActions: String { isSpanish ? "Acciones Rápidas" : "Quick Actions" }
    static var about: String { isSpanish ? "Acerca de" : "About" }
    static var version: String { isSpanish ? "Versión" : "Version" }

    // MARK: - Common Actions
    static var cancel: String { isSpanish ? "Cancelar" : "Cancel" }
    static var save: String { isSpanish ? "Guardar" : "Save" }
    static var create: String { isSpanish ? "Crear" : "Create" }
    static var delete: String { isSpanish ? "Eliminar" : "Delete" }
    static var ok: String { isSpanish ? "Aceptar" : "OK" }
    static var done: String { isSpanish ? "Listo" : "Done" }

    // MARK: - Watch History
    static var watchHistory: String { isSpanish ? "Historial de Visualización" : "Watch History" }
    static var noHistory: String { isSpanish ? "Sin Historial" : "No Watch History" }
    static var historyDescription: String { isSpanish ? "Las películas y series que veas aparecerán aquí" : "Movies and shows you watch will appear here" }

    // MARK: - Custom Lists
    static var noLists: String { isSpanish ? "Sin Listas" : "No Lists Yet" }
    static var listsDescription: String { isSpanish ? "Crea listas personalizadas para organizar tu contenido" : "Create custom lists to organize your content" }
    static var newList: String { isSpanish ? "Nueva Lista" : "New List" }
    static var listName: String { isSpanish ? "Nombre de Lista" : "List Name" }
    static var listDescription: String { isSpanish ? "Descripción (opcional)" : "Description (optional)" }
    static var privacy: String { isSpanish ? "Privacidad" : "Privacy" }
    static var publicList: String { isSpanish ? "Público" : "Public" }
    static var privateList: String { isSpanish ? "Privado" : "Private" }
    static var anyoneCanSee: String { isSpanish ? "Cualquiera puede ver esta lista" : "Anyone can see this list" }
    static var onlyYou: String { isSpanish ? "Solo tú puedes ver esta lista" : "Only you can see this list" }

    // MARK: - Notifications
    static var notifications: String { isSpanish ? "Notificaciones" : "Notifications" }

    // MARK: - Movie Info
    static var addToWatchlist: String { isSpanish ? "Agregar a Lista" : "Add to Watchlist" }
    static var markAsSeen: String { isSpanish ? "Marcar como Visto" : "Mark as Seen" }
    static var rate: String { isSpanish ? "Calificar" : "Rate" }
    static var cast: String { isSpanish ? "Reparto" : "Cast" }
    static var similarMovies: String { isSpanish ? "Películas Similares" : "Similar Movies" }
    static var whereToWatch: String { isSpanish ? "Dónde Ver" : "Where to Watch" }

    // MARK: - Watch With
    static var watchWith: String { isSpanish ? "Ver Con Amigo" : "Watch With a Friend" }
    static var pickAFriend: String { isSpanish ? "Elige un amigo" : "Pick a Friend" }
    static var noFriendsYet: String { isSpanish ? "Sin Amigos" : "No Friends Yet" }
    static var noFriendsDescription: String { isSpanish ? "Sigue a alguien para comparar puntuaciones predichas" : "Follow someone to compare predicted scores" }
    static var calculatingPrediction: String { isSpanish ? "Calculando predicción..." : "Calculating prediction..." }
    static var you: String { isSpanish ? "Tú" : "You" }
    static var whyThisScore: String { isSpanish ? "¿Por qué esta puntuación?" : "Why this score?" }
    static var chooseDifferentFriend: String { isSpanish ? "Elegir otro amigo" : "Choose Different Friend" }
    static var greatPick: String { isSpanish ? "¡Gran elección para ambos!" : "Great pick for both of you!" }
    static var solidChoice: String { isSpanish ? "Buena opción" : "Solid choice" }
    static var mightDisagree: String { isSpanish ? "Podrían no estar de acuerdo" : "You might disagree on this one" }
    static var maybeSkip: String { isSpanish ? "Quizás omitir esta" : "Maybe skip this one" }
    static var couldWork: String { isSpanish ? "Podría funcionar" : "Could work" }
    static var combinedScore: String { isSpanish ? "Puntuación combinada" : "Combined score" }
    static var theirActualScore: String { isSpanish ? "Su puntuación real" : "Their actual score" }
    static var predicted: String { isSpanish ? "predicción" : "predicted" }
}
