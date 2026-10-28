import Foundation
import MapKit

/// Apple Maps behind the Location field: `MKLocalSearchCompleter` for the suggestions while typing,
/// `MKLocalSearch` to resolve a picked one to a map item (name, coordinate, address). Needs no
/// location permission and no API key. Every call stays on the main actor; the completer reports
/// there.
@MainActor
final class MapsPlaceSearch: NSObject, PlaceSearchService, MKLocalSearchCompleterDelegate {
    var onUpdate: ((PlaceSearchUpdate) -> Void)?

    private let completer = MKLocalSearchCompleter()
    /// The completions behind the rows last reported (kept until newer results replace them).
    private var completions = SuggestionTable<MKLocalSearchCompletion>()

    enum SearchError: Error { case unknownSuggestion, notFound }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func search(_ query: String) {
        // The rows on screen stay pickable until the new results replace them (`publishResults`).
        completer.queryFragment = query
    }

    func cancel() {
        completer.cancel()
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> PickedPlace {
        guard let completion = completions.handle(for: suggestion) else { throw SearchError.unknownSuggestion }
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        // Not cancelled when it goes stale: the model drops a stale answer.
        let response = try await search.start()
        guard let item = response.mapItems.first else { throw SearchError.notFound }
        return Self.place(from: item, fallback: suggestion)
    }

    nonisolated private static func place(from item: MKMapItem, fallback: PlaceSuggestion) -> PickedPlace {
        let coordinate = item.location.coordinate
        let address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.shortAddress
            ?? item.address?.fullAddress
            ?? (fallback.subtitle.isEmpty ? nil : fallback.subtitle)
        let name = item.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback.title
        return PickedPlace(name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onMain { $0.publishResults() }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let nothingFound = (error as? MKError)?.code == .placemarkNotFound
        onMain { search in
            let query = search.completer.queryFragment
            search.onUpdate?(nothingFound ? .results(query: query, []) : .failed(query: query))
        }
    }

    /// The completer calls back on the main thread; the API does not promise it, so check.
    nonisolated private func onMain(_ body: @escaping @MainActor (MapsPlaceSearch) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body(self) }
        } else {
            DispatchQueue.main.async { body(self) }
        }
    }

    private func publishResults() {
        let rows = completions.publish(completer.results.prefix(PlaceSearchModel.maxRows).map {
            (title: $0.title, subtitle: $0.subtitle, handle: $0)
        })
        onUpdate?(.results(query: completer.queryFragment, rows))
    }
}
