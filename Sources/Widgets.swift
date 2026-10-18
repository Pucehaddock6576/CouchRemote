// Widgets.swift — little info bits in the Big Screen header: Mac battery, next calendar event, weather
import AppKit
import Combine
import EventKit
import IOKit.ps

final class Widgets: ObservableObject {
    static let shared = Widgets()

    @Published private(set) var battery: (percent: Int, charging: Bool)?
    @Published private(set) var nextEvent: (title: String, when: String)?
    @Published private(set) var weather: (temp: String, symbol: String, place: String)?
    @Published private(set) var calendarStatus = ""
    @Published private(set) var weatherStatus = ""

    private var timer: Timer?
    private var lastCalendar = Date.distantPast
    private var lastWeather = Date.distantPast
    private var weatherFor = ""
    private let events = EKEventStore()

    /// Starts refreshing (cheap: battery every minute, calendar every 5 minutes, weather every 30 minutes)
    func start() {
        refresh(force: false)
        guard timer == nil else { return }
        timer = Timer.common(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh(force: false) }
    }

    func refresh(force: Bool) {
        let s = ConfigStore.shared.settings
        battery = s.widgetBattery ? Self.readBattery() : nil
        if s.widgetCalendar || s.bigWidgets.contains("calendar") {
            if force || Date().timeIntervalSince(lastCalendar) > 300 { lastCalendar = Date(); loadCalendar() }
        } else { nextEvent = nil }
        if s.widgetWeather || s.bigWidgets.contains("weather") {   // an empty city means: work it out from your connection
            let key = s.weatherCity + (s.weatherCelsius ? "C" : "F")
            if force || key != weatherFor || Date().timeIntervalSince(lastWeather) > 1800 {
                lastWeather = Date(); weatherFor = key; loadWeather(city: s.weatherCity, celsius: s.weatherCelsius)
            }
        } else { weather = nil; forecast = nil }
    }

    // MARK: battery

    private static func readBattery() -> (percent: Int, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let maxCap = d[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            return (percent: Int((Double(cur) / Double(maxCap) * 100).rounded()), charging: charging)
        }
        return nil      // desktop Macs have no battery
    }

    // MARK: calendar

    func requestCalendar(done: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
        if #available(macOS 14.0, *) {
            events.requestFullAccessToEvents(completion: finish)
        } else {
            events.requestAccess(to: .event, completion: finish)
        }
    }

    private func calendarAllowed() -> Bool {
        let st = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return st == .fullAccess }
        return st == .authorized
    }

    private func loadCalendar() {
        guard calendarAllowed() else {
            nextEvent = nil
            calendarStatus = "Calendar access is off. Click “Allow calendar” in Big Screen settings."
            return
        }
        calendarStatus = ""
        let now = Date()
        let pred = events.predicateForEvents(withStart: now, end: now.addingTimeInterval(36 * 3600), calendars: nil)
        let next = events.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
        guard let e = next else { nextEvent = nil; return }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        var when = e.startDate <= now ? "Now" : f.string(from: e.startDate)
        if !Calendar.current.isDateInToday(e.startDate) && e.startDate > now { when = "Tomorrow " + when }
        nextEvent = (title: e.title ?? "Event", when: when)
    }

    // MARK: weather (Open-Meteo: free, no account or key)

    struct WeatherDay: Identifiable { let id = UUID(); var day: String; var symbol: String; var hi: Int; var lo: Int; var rain: Int }
    struct WeatherHour: Identifiable { let id = UUID(); var time: String; var symbol: String; var temp: Int }
    struct WeatherDetails {
        var place: String
        var temp: Int, feels: Int, hi: Int, lo: Int
        var symbol: String, summary: String
        var humidity: Int, wind: Int, windUnit: String, uv: Int?
        var sunrise: String, sunset: String
        var hours: [WeatherHour]
        var days: [WeatherDay]
    }
    @Published private(set) var forecast: WeatherDetails?

    private struct Geo: Decodable {
        struct Place: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Place]?
    }
    private struct IPPlace: Decodable { let city: String?; let latitude: Double?; let longitude: Double? }
    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double; let weather_code: Int; let is_day: Int?
            let apparent_temperature: Double?; let relative_humidity_2m: Double?; let wind_speed_10m: Double?
        }
        struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int] }
        struct Daily: Decodable {
            let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?; let sunrise: [String]?; let sunset: [String]?; let uv_index_max: [Double?]?
        }
        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }


    private func loadWeather(city: String, celsius: Bool) {
        let trimmed = city.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard let u = URL(string: "https://ipwho.is/") else { return }
            URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 15)) { [weak self] data, _, _ in
                guard let self = self else { return }
                guard let ip = data.flatMap({ try? JSONDecoder().decode(IPPlace.self, from: $0) }),
                      let lat = ip.latitude, let lon = ip.longitude else {
                    DispatchQueue.main.async { self.weatherStatus = "Couldn’t work out where you are. Type your city in Big Screen settings." }
                    return
                }
                self.loadForecast(place: ip.city ?? "Here", lat: lat, lon: lon, celsius: celsius)
            }.resume()
            return
        }
        var g = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        g.queryItems = [URLQueryItem(name: "name", value: trimmed), URLQueryItem(name: "count", value: "1")]
        guard let gurl = g.url else { return }
        URLSession.shared.dataTask(with: gurl) { [weak self] data, _, _ in
            guard let self = self else { return }
            guard let data = data, let geo = try? JSONDecoder().decode(Geo.self, from: data), let p = geo.results?.first else {
                DispatchQueue.main.async { self.weather = nil; self.forecast = nil; self.weatherStatus = "Couldn't find “\(trimmed)”. Try a nearby city name." }
                return
            }
            self.loadForecast(place: p.name, lat: p.latitude, lon: p.longitude, celsius: celsius)
        }.resume()
    }

    private func loadForecast(place: String, lat: Double, lon: Double, celsius: Bool) {
        var f = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        f.queryItems = [URLQueryItem(name: "latitude", value: String(lat)),
                        URLQueryItem(name: "longitude", value: String(lon)),
                        URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day,apparent_temperature,relative_humidity_2m,wind_speed_10m"),
                        URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
                        URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"),
                        URLQueryItem(name: "forecast_days", value: "6"),
                        URLQueryItem(name: "timezone", value: "auto"),
                        URLQueryItem(name: "temperature_unit", value: celsius ? "celsius" : "fahrenheit"),
                        URLQueryItem(name: "wind_speed_unit", value: celsius ? "kmh" : "mph")]
        guard let furl = f.url else { return }
        URLSession.shared.dataTask(with: furl) { data, _, _ in
            let fc = data.flatMap { try? JSONDecoder().decode(Forecast.self, from: $0) }
            DispatchQueue.main.async {
                guard let fc = fc else { self.weatherStatus = "Weather is unavailable right now."; return }
                let c = fc.current
                let day = (c.is_day ?? 1) == 1
                self.weatherStatus = ""
                self.weather = (temp: "\(Int(c.temperature_2m.rounded()))°", symbol: Self.symbol(c.weather_code, day: day), place: place)
                self.forecast = Self.details(fc, place: place, day: day, celsius: celsius)
            }
        }.resume()
    }

    private static func details(_ fc: Forecast, place: String, day: Bool, celsius: Bool) -> WeatherDetails {
        let c = fc.current
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd'T'HH:mm"; iso.locale = Locale(identifier: "en_US_POSIX")
        let dayISO = DateFormatter(); dayISO.dateFormat = "yyyy-MM-dd"; dayISO.locale = Locale(identifier: "en_US_POSIX")
        let hourOut = DateFormatter(); hourOut.setLocalizedDateFormatFromTemplate("j")
        let timeOut = DateFormatter(); timeOut.timeStyle = .short; timeOut.dateStyle = .none
        let dayOut = DateFormatter(); dayOut.setLocalizedDateFormatFromTemplate("EEE")

        var hours: [WeatherHour] = []
        if let h = fc.hourly {
            // The next 12 hours, starting from this one (the API's times are local to the place)
            let nowKey = iso.string(from: Date()).prefix(13)
            let start = h.time.firstIndex(where: { $0.prefix(13) >= nowKey }) ?? 0
            for i in start..<min(start + 12, h.time.count, h.temperature_2m.count, h.weather_code.count) {
                let label = i == start ? "Now" : (iso.date(from: h.time[i]).map { hourOut.string(from: $0) } ?? "")
                hours.append(WeatherHour(time: label, symbol: symbol(h.weather_code[i], day: true), temp: Int(h.temperature_2m[i].rounded())))
            }
        }
        var days: [WeatherDay] = []
        var hi = Int(c.temperature_2m.rounded()), lo = hi, uv: Int?, sunrise = "", sunset = ""
        if let d = fc.daily {
            let n = min(d.time.count, d.weather_code.count, d.temperature_2m_max.count, d.temperature_2m_min.count)
            for i in 0..<n {
                let name = i == 0 ? "Today" : (dayISO.date(from: d.time[i]).map { dayOut.string(from: $0) } ?? d.time[i])
                let rain = d.precipitation_probability_max.flatMap { i < $0.count ? $0[i] : nil } ?? 0
                days.append(WeatherDay(day: name, symbol: symbol(d.weather_code[i], day: true),
                                       hi: Int(d.temperature_2m_max[i].rounded()), lo: Int(d.temperature_2m_min[i].rounded()), rain: rain))
            }
            if let t = days.first { hi = t.hi; lo = t.lo }
            if let u = d.uv_index_max, let first = u.first, let v = first { uv = Int(v.rounded()) }
            if let s = d.sunrise?.first, let dt = iso.date(from: s) { sunrise = timeOut.string(from: dt) }
            if let s = d.sunset?.first, let dt = iso.date(from: s) { sunset = timeOut.string(from: dt) }
        }
        return WeatherDetails(place: place, temp: Int(c.temperature_2m.rounded()), feels: Int((c.apparent_temperature ?? c.temperature_2m).rounded()),
                              hi: hi, lo: lo, symbol: symbol(c.weather_code, day: day), summary: describe(c.weather_code),
                              humidity: Int((c.relative_humidity_2m ?? 0).rounded()), wind: Int((c.wind_speed_10m ?? 0).rounded()),
                              windUnit: celsius ? "km/h" : "mph", uv: uv, sunrise: sunrise, sunset: sunset, hours: hours, days: days)
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorms"
        default: return "—"
        }
    }

    static func symbol(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
