import CCCore
import Foundation

/// Open-Meteo — free, keyless, precise enough for "rain from 16:00 in
/// Wortegem". Refreshed every 30 minutes while watched.
@MainActor
final class WeatherProvider: PollingProvider {
    override var channels: Set<Channel> { [.weather] }
    override var interval: TimeInterval { 1800 }

    private struct Response: Decodable {
        struct Current: Decodable {
            let time: Double
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let wind_speed_10m: Double
            let is_day: Int
        }

        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let precipitation_probability: [Int?]
            let is_day: [Int]
        }

        struct Daily: Decodable {
            let time: [Double]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]
            let sunrise: [Double]
            let sunset: [Double]
        }

        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    func preferencesChanged() { kick() }

    override func tick() async {
        guard Hub.shared.integrations.weatherEnabled else { return }
        let preferences = Hub.shared.workspace.preferences
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(preferences.latitude)),
            URLQueryItem(name: "longitude", value: String(preferences.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let response = try JSONDecoder().decode(Response.self, from: data)
            let now = Date()
            var hourly: [HourForecast] = []
            for index in response.hourly.time.indices {
                let time = Date(timeIntervalSince1970: response.hourly.time[index])
                guard time > now.addingTimeInterval(-1800), hourly.count < 12 else { continue }
                hourly.append(HourForecast(
                    time: time,
                    temperature: response.hourly.temperature_2m[index],
                    code: response.hourly.weather_code[index],
                    precipitationChance: response.hourly.precipitation_probability[index] ?? 0,
                    isDay: response.hourly.is_day[index] == 1
                ))
            }
            let state = WeatherState(
                location: preferences.weatherLocation,
                temperature: response.current.temperature_2m,
                apparent: response.current.apparent_temperature,
                code: response.current.weather_code,
                isDay: response.current.is_day == 1,
                high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
                low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m,
                precipitationChance: response.daily.precipitation_probability_max.first.flatMap { $0 } ?? 0,
                wind: response.current.wind_speed_10m,
                hourly: hourly,
                sunrise: response.daily.sunrise.first.map { Date(timeIntervalSince1970: $0) },
                sunset: response.daily.sunset.first.map { Date(timeIntervalSince1970: $0) },
                updatedAt: now
            )
            Hub.shared.publish(.weather(state))
        } catch {
            Log.shared.warning("Weather refresh failed: \(error.localizedDescription)")
        }
    }
}
