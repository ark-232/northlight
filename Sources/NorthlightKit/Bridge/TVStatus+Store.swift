import Foundation

extension DashboardStore {
    /// What the TV tells the Mac's mirror. `full` adds the flights, latency and speed
    /// history, the readings that cost the most bytes, which go every 30 s at most.
    public func status(editing: Bool, page: UUID?, full: Bool) -> TVStatus {
        var status = TVStatus(editing: editing, page: page)
        status.place = config.place
        status.units = units
        status.flightRadiusNM = config.flightRadiusNM
        status.path = path
        status.weather = weather
        status.alerts = alerts
        status.aurora = aurora
        status.quakes = quakes
        status.airQuality = airQuality
        status.spaceWeather = spaceWeather
        status.xrays = xrays
        status.iss = iss
        status.launches = launches
        status.hackerNews = hackerNews
        status.serviceStatus = serviceStatus
        status.crypto = crypto
        status.rates = rates
        if full {
            status.flights = flights
            status.latency = latency
            status.speed = Array(speedTests.suffix(30))
        }
        return status
    }
}
