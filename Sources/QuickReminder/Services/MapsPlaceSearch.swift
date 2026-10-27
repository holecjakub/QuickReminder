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
    /// The completions behind the rows reported for the current query, by row id.
    private var completions: [Int: MKLocalSearchCompletion] = [:]
    private var nextID = 0

    enum SearchError: Error { case unknownSuggestion, notFound }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func search(_ query: String) {
        // Rows of an earlier query can no longer be picked; refinements of this one stay valid.
        completions.removeAll(keepingCapacity: true)
        completer.queryFragment = query
    }

    func cancel() {
        completer.cancel()
    }

    func resolve(_ suggestion: PlaceSuggestion) async throws -> PickedPlace {
        guard let completion = completions[suggestion.id] else { throw SearchError.unknownSuggestion }
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        // Not cancelled when it goes stale: the model drops a stale answer, and a cancelled search
        // is not guaranteed to call back (the continuation must resume exactly once).
        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let item = response?.mapItems.first {
                    continuation.resume(returning: Self.place(from: item, fallback: suggestion))
                } else {
                    continuation.resume(throwing: error ?? SearchError.notFound)
                }
            }
        }
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
        var rows: [PlaceSuggestion] = []
        for completion in completer.results.prefix(PlaceSearchModel.maxRows) {
            nextID += 1
            completions[nextID] = completion
            rows.append(PlaceSuggestion(id: nextID, title: completion.title, subtitle: completion.subtitle))
        }
        onUpdate?(.results(query: completer.queryFragment, rows))
    }
}
