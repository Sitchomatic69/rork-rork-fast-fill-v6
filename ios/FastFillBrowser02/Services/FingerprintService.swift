import Foundation
import SwiftUI

/// Curated locale + timezone choice exposed in Settings.
struct FingerprintLocale: Identifiable, Hashable {
    let id: String          // BCP-47 code, e.g. "en-AU". Empty means "system default".
    let label: String
    let suggestedTimezone: String
}

struct FingerprintTimezone: Identifiable, Hashable {
    let id: String          // IANA, e.g. "Australia/Perth". Empty means "system default".
    let label: String
}

/// Owns the per-session randomized "fingerprint" — User-Agent, locale, and
/// timezone overrides — that every WKWebView in the app applies. Single mode
/// gets one fingerprint per app launch; each Quad cell (S1–S4) gets its own
/// persistent fingerprint stored in UserDefaults.
@Observable
@MainActor
final class FingerprintService {
    static let shared = FingerprintService()

    // MARK: - Curated lists

    static let locales: [FingerprintLocale] = [
        .init(id: "",      label: "System default",        suggestedTimezone: ""),
        .init(id: "en-AU", label: "English (Australia)",   suggestedTimezone: "Australia/Perth"),
        .init(id: "en-US", label: "English (US)",          suggestedTimezone: "America/New_York"),
        .init(id: "en-GB", label: "English (UK)",          suggestedTimezone: "Europe/London"),
        .init(id: "en-CA", label: "English (Canada)",      suggestedTimezone: "America/Toronto"),
        .init(id: "fr-FR", label: "French (France)",       suggestedTimezone: "Europe/Paris"),
        .init(id: "de-DE", label: "German (Germany)",      suggestedTimezone: "Europe/Berlin"),
        .init(id: "es-ES", label: "Spanish (Spain)",       suggestedTimezone: "Europe/Madrid"),
        .init(id: "it-IT", label: "Italian (Italy)",       suggestedTimezone: "Europe/Rome"),
        .init(id: "ja-JP", label: "Japanese (Japan)",      suggestedTimezone: "Asia/Tokyo"),
        .init(id: "pt-BR", label: "Portuguese (Brazil)",   suggestedTimezone: "America/Sao_Paulo"),
        .init(id: "nl-NL", label: "Dutch (Netherlands)",   suggestedTimezone: "Europe/Amsterdam"),
    ]

    static let timezones: [FingerprintTimezone] = [
        .init(id: "",                       label: "System default"),
        .init(id: "Australia/Perth",        label: "Australia/Perth"),
        .init(id: "Australia/Sydney",       label: "Australia/Sydney"),
        .init(id: "America/New_York",       label: "America/New_York"),
        .init(id: "America/Los_Angeles",    label: "America/Los_Angeles"),
        .init(id: "America/Toronto",        label: "America/Toronto"),
        .init(id: "America/Sao_Paulo",      label: "America/Sao_Paulo"),
        .init(id: "Europe/London",          label: "Europe/London"),
        .init(id: "Europe/Paris",           label: "Europe/Paris"),
        .init(id: "Europe/Berlin",          label: "Europe/Berlin"),
        .init(id: "Europe/Madrid",          label: "Europe/Madrid"),
        .init(id: "Europe/Rome",            label: "Europe/Rome"),
        .init(id: "Europe/Amsterdam",       label: "Europe/Amsterdam"),
        .init(id: "Asia/Tokyo",             label: "Asia/Tokyo"),
    ]

    // MARK: - State

    /// User-Agent for single-mode browsing. Re-rolled on app launch and on
    /// every manual Regenerate tap.
    private(set) var singleUserAgent: String

    /// Persistent per-cell User-Agents (S1…S4). Survive launches.
    private(set) var cellUserAgents: [String]

    var locale: String {
        didSet {
            UserDefaults.standard.set(locale, forKey: Keys.locale)
        }
    }
    var timezone: String {
        didSet {
            UserDefaults.standard.set(timezone, forKey: Keys.timezone)
        }
    }

    private enum Keys {
        static let locale = "fp_locale"
        static let timezone = "fp_timezone"
        static let cellUAPrefix = "fp_cell_ua_"
    }

    private init() {
        self.singleUserAgent = Self.generateRandomUserAgent()
        self.locale = UserDefaults.standard.string(forKey: Keys.locale) ?? ""
        self.timezone = UserDefaults.standard.string(forKey: Keys.timezone) ?? ""
        // Load (or initialize) per-cell UAs.
        var cells: [String] = []
        for i in 0..<4 {
            let key = Keys.cellUAPrefix + String(i)
            if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
                cells.append(saved)
            } else {
                let ua = Self.generateRandomUserAgent()
                UserDefaults.standard.set(ua, forKey: key)
                cells.append(ua)
            }
        }
        self.cellUserAgents = cells
    }

    // MARK: - Accessors

    /// Returns the User-Agent for the requested context. `cellIndex == nil`
    /// uses the single-mode UA; `0…3` returns the persistent cell UA.
    func userAgent(forCell cellIndex: Int?) -> String {
        if let cellIndex, cellUserAgents.indices.contains(cellIndex) {
            return cellUserAgents[cellIndex]
        }
        return singleUserAgent
    }

    /// Re-rolls the single-mode UA.
    func regenerateSingle() {
        singleUserAgent = Self.generateRandomUserAgent()
    }

    /// Re-rolls a specific quad cell's persistent UA.
    func regenerateCell(_ cellIndex: Int) {
        guard cellUserAgents.indices.contains(cellIndex) else { return }
        let ua = Self.generateRandomUserAgent()
        cellUserAgents[cellIndex] = ua
        UserDefaults.standard.set(ua, forKey: Keys.cellUAPrefix + String(cellIndex))
    }

    /// Sets the locale and, if the timezone is still "system default", pairs
    /// it with the locale's suggested timezone for convenience.
    func setLocale(_ id: String) {
        locale = id
        if timezone.isEmpty {
            if let match = Self.locales.first(where: { $0.id == id }), !match.suggestedTimezone.isEmpty {
                timezone = match.suggestedTimezone
            }
        }
    }

    // MARK: - Override script

    /// Injectable JS that overrides `navigator.language`, `navigator.languages`,
    /// `Intl.DateTimeFormat().resolvedOptions().timeZone`, and `Date`'s implicit
    /// timezone. Safe to inject at `documentStart` on every navigation.
    func overrideScript() -> String {
        let loc = locale
        let tz = timezone
        guard !loc.isEmpty || !tz.isEmpty else { return "" }

        let safeLocale = loc.jsEscaped
        let safeTimezone = tz.jsEscaped
        // Build a JS-array literal of language fallbacks.
        let languagesJS: String
        if loc.isEmpty {
            languagesJS = "null"
        } else if loc.contains("-") {
            let base = String(loc.split(separator: "-").first ?? "")
            languagesJS = "['\(safeLocale)','\(base.jsEscaped)']"
        } else {
            languagesJS = "['\(safeLocale)']"
        }

        return """
        (function() {
            try {
                var loc = '\(safeLocale)';
                var tz = '\(safeTimezone)';
                if (loc) {
                    try { Object.defineProperty(navigator, 'language',  { get: function() { return loc; }, configurable: true }); } catch(e) {}
                    var langs = \(languagesJS);
                    if (langs) {
                        try { Object.defineProperty(navigator, 'languages', { get: function() { return langs; }, configurable: true }); } catch(e) {}
                    }
                }
                if (tz) {
                    try {
                        var _DTF = Intl.DateTimeFormat;
                        var Patched = function() {
                            var args = Array.prototype.slice.call(arguments);
                            var locales = args[0];
                            var options = args[1] || {};
                            if (!options.timeZone) { options.timeZone = tz; }
                            if (loc && !locales) { locales = loc; }
                            return new _DTF(locales, options);
                        };
                        Patched.prototype = _DTF.prototype;
                        Patched.supportedLocalesOf = _DTF.supportedLocalesOf;
                        Intl.DateTimeFormat = Patched;
                    } catch(e) {}
                    // Best-effort: also override Date#toString-family timezone
                    // by intercepting getTimezoneOffset.
                    try {
                        var offsetMinutes = (function() {
                            try {
                                var dtf = new _DTF('en-US', { timeZone: tz, timeZoneName: 'shortOffset' });
                                var parts = dtf.formatToParts(new Date());
                                for (var i = 0; i < parts.length; i++) {
                                    if (parts[i].type === 'timeZoneName') {
                                        var v = parts[i].value;
                                        var m = v.match(/GMT([+-])(\\d{1,2})(?::?(\\d{2}))?/);
                                        if (m) {
                                            var sign = (m[1] === '-') ? 1 : -1;
                                            var h = parseInt(m[2], 10) || 0;
                                            var mm = parseInt(m[3] || '0', 10) || 0;
                                            return sign * (h * 60 + mm);
                                        }
                                    }
                                }
                            } catch(e) {}
                            return null;
                        })();
                        if (offsetMinutes !== null) {
                            try { Date.prototype.getTimezoneOffset = function() { return offsetMinutes; }; } catch(e) {}
                        }
                    } catch(e) {}
                }
            } catch (e) {}
        })();
        """
    }

    // MARK: - Random UA

    private static let iosVersions: [(major: Int, minor: Int, patch: Int)] = [
        (16, 4, 1), (16, 5, 0), (16, 6, 1), (16, 7, 0),
        (17, 0, 3), (17, 1, 2), (17, 2, 1), (17, 3, 1), (17, 4, 1), (17, 5, 1), (17, 6, 1), (17, 7, 0),
        (18, 0, 0), (18, 1, 0), (18, 1, 1), (18, 2, 0), (18, 3, 0)
    ]

    private static let webkitBuilds: [String] = [
        "605.1.15", "605.1.14"
    ]

    private static let mobileBuilds: [String] = [
        "15E148", "21A329", "21B91", "21C66", "21D50", "21E236",
        "21F90", "21G93", "21H16", "22A340", "22B91", "22D60"
    ]

    /// Generates a Safari-on-iPhone style User-Agent with randomized version
    /// numbers within a plausible range. Designed to look like a real device,
    /// not a custom string, so sites don't block it.
    static func generateRandomUserAgent() -> String {
        let ios = iosVersions.randomElement() ?? (17, 5, 1)
        let osVer = "\(ios.major)_\(ios.minor)_\(ios.patch)"
        let safariVer = "\(ios.major).\(ios.minor)"
        let webkit = webkitBuilds.randomElement() ?? "605.1.15"
        let mobile = mobileBuilds.randomElement() ?? "15E148"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVer) like Mac OS X) AppleWebKit/\(webkit) (KHTML, like Gecko) Version/\(safariVer) Mobile/\(mobile) Safari/604.1"
    }

    // MARK: - Display helpers

    var localeDisplay: String {
        if locale.isEmpty { return "System default" }
        return Self.locales.first(where: { $0.id == locale })?.label ?? locale
    }

    var timezoneDisplay: String {
        if timezone.isEmpty { return "System default" }
        return timezone
    }

    func uaSuffix(_ ua: String, maxLen: Int = 24) -> String {
        guard ua.count > maxLen else { return ua }
        return "…" + String(ua.suffix(maxLen))
    }
}
