import SwiftUI
import NorthlightUI

/// The data sources, credited as their terms ask.
struct About: View {
    private struct Credit: Hashable {
        let source: String
        let use: String
        let address: String
    }

    private static let credits = [
        Credit(source: "Open-Meteo", use: "Weather, forecasts, air quality and snow. Weather data by Open-Meteo.com, under CC BY 4.0.",
               address: "open-meteo.com · creativecommons.org/licenses/by/4.0"),
        Credit(source: "Copernicus Atmosphere Monitoring Service",
               use: "Air quality, from the CAMS ensemble forecasts through Open-Meteo, under the Copernicus CC BY license.",
               address: "atmosphere.copernicus.eu"),
        Credit(source: "National Weather Service", use: "Weather alerts in the United States.", address: "weather.gov"),
        Credit(source: "adsb.fi", use: "Aircraft overhead, from its open data for personal, non-commercial use.", address: "adsb.fi"),
        Credit(source: "U.S. Geological Survey", use: "Earthquakes courtesy of the U.S. Geological Survey.", address: "earthquake.usgs.gov"),
        Credit(source: "NOAA Space Weather Prediction Center",
               use: "The aurora forecast, the Kp index, the solar wind, GOES X-ray flux and flares, and the NOAA space weather scales.",
               address: "swpc.noaa.gov"),
        Credit(source: "Where the ISS at?", use: "The space station's position, from its public API.", address: "wheretheiss.at"),
        Credit(source: "The Space Devs", use: "Upcoming launches, from Launch Library 2.", address: "thespacedevs.com"),
        Credit(source: "Hacker News", use: "Top stories, from the Hacker News API.", address: "news.ycombinator.com"),
        Credit(source: "GitHub Status and Claude Status", use: "Service status, from the public Statuspage summaries of GitHub and Anthropic.",
               address: "githubstatus.com · status.claude.com"),
        Credit(source: "CISA", use: "The Known Exploited Vulnerabilities catalog, under CC0 1.0.", address: "cisa.gov/known-exploited-vulnerabilities-catalog"),
        Credit(source: "Kraken", use: "Bitcoin and ether prices, from Kraken's public market data.", address: "kraken.com"),
        Credit(source: "Frankfurter", use: "Dollar exchange rates, from the European Central Bank's reference rates through Frankfurter.",
               address: "frankfurter.dev"),
        Credit(source: "Apple Maps", use: "Place search, time zones, and the flight and ISS maps.", address: "apple.com/maps"),
    ]

    var body: some View {
        ZStack {
            SkyField()
            // Every credit takes focus, so the remote scrolls the ones below the fold into view.
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    Text("About Northlight")
                        .font(Theme.Font.clock)
                        .foregroundStyle(Theme.Palette.bone)
                    Grid(alignment: .topLeading, horizontalSpacing: 60, verticalSpacing: 36) {
                        ForEach(Array(stride(from: 0, to: Self.credits.count, by: 3)), id: \.self) { start in
                            GridRow {
                                ForEach(Self.credits[start..<min(start + 3, Self.credits.count)], id: \.self) { credit in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(credit.source)
                                            .font(Theme.Font.title)
                                            .foregroundStyle(Theme.Palette.bone)
                                        Text(credit.use)
                                            .font(Theme.Font.body)
                                            .foregroundStyle(Theme.Palette.muted)
                                        Text(credit.address)
                                            .font(Theme.Font.caption)
                                            .foregroundStyle(Theme.Palette.faint)
                                    }
                                    .frame(maxWidth: 540, alignment: .leading)
                                    .focusable()
                                }
                            }
                        }
                    }
                    Text(version)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
