import MapKit
import SwiftUI
import UIKit

struct MapCamera: Equatable {
    var latitude: Double
    var longitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double

    static let world = MapCamera(latitude: 20, longitude: 0, latitudeDelta: 80, longitudeDelta: 80)

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    init(latitude: Double, longitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }

    init(region: MKCoordinateRegion) {
        latitude = region.center.latitude
        longitude = region.center.longitude
        latitudeDelta = region.span.latitudeDelta
        longitudeDelta = region.span.longitudeDelta
    }
}

@MainActor
@Observable
final class MapModel: NSObject, MKLocalSearchCompleterDelegate {
    var events: [EventSummary] = []
    var selectedID: UUID?
    var category: EventCategory?
    var joinedOnly = false
    var query = ""
    var suggestions: [MKLocalSearchCompletion] = []
    var camera = MapCamera.world
    var focusToken = UUID()
    var error: String?
    var isLoading = false
    var didCenterOnUser = false

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func reload() async {
        isLoading = events.isEmpty
        defer { isLoading = false }
        var filter = EventQuery(
            south: camera.latitude - camera.latitudeDelta / 2,
            north: camera.latitude + camera.latitudeDelta / 2,
            west: camera.longitude - camera.longitudeDelta / 2,
            east: camera.longitude + camera.longitudeDelta / 2,
            category: category,
            endingAfter: Date(),
            joinedOnly: joinedOnly,
            limit: 200
        )
        if camera.latitudeDelta > 40 {
            filter.south = nil
            filter.north = nil
            filter.west = nil
            filter.east = nil
            filter.limit = 80
        }
        do {
            events = try await app.repository.events(filter: filter)
            error = nil
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    func scheduleReload() {
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func select(_ id: UUID) {
        selectedID = id
        guard let event = events.first(where: { $0.id == id }) else { return }
        var next = camera
        next.latitude = event.event.latitude
        next.longitude = event.event.longitude
        if next.latitudeDelta > 0.4 || next.longitudeDelta > 0.4 {
            next.latitudeDelta = 0.15
            next.longitudeDelta = 0.15
        }
        camera = next
        focusToken = UUID()
    }

    func center(on location: CLLocation) {
        didCenterOnUser = true
        camera = MapCamera(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, latitudeDelta: 0.18, longitudeDelta: 0.18)
        focusToken = UUID()
        scheduleReload()
    }

    func updateCamera(_ region: MKCoordinateRegion) {
        let next = MapCamera(region: region)
        let moved = abs(next.latitude - camera.latitude) > 0.002 || abs(next.longitude - camera.longitude) > 0.002
            || abs(next.latitudeDelta - camera.latitudeDelta) > 0.01
        camera = next
        if moved { scheduleReload() }
    }

    func search() {
        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        completer.queryFragment = fragment
        if fragment.isEmpty { suggestions = [] }
    }

    func choose(_ completion: MKLocalSearchCompletion) async {
        do {
            let place = try await PlaceSearch.coordinate(for: completion)
            query = ""
            suggestions = []
            camera = MapCamera(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, latitudeDelta: 0.2, longitudeDelta: 0.2)
            focusToken = UUID()
            await reload()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        nonisolated(unsafe) let results = completer.results
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}

struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: MapModel?
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let model {
                    map(model)
                } else {
                    NightshiftColor.background
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            let active: MapModel
            if let model {
                active = model
            } else {
                let created = MapModel(app: app)
                model = created
                active = created
            }
            if location.authorization == .notDetermined {
                location.requestAccess()
            } else {
                location.refresh()
            }
            await active.reload()
            for await signal in app.repository.changes() {
                if signal == .events { await active.reload() }
            }
        }
        .onChange(of: location.location) { _, newValue in
            guard let newValue, let model, !model.didCenterOnUser else { return }
            model.center(on: newValue)
        }
    }

    @ViewBuilder
    private func map(_ model: MapModel) -> some View {
        GeometryReader { proxy in
            let avoid = NightshiftLayout.avoidance(in: proxy)
            ZStack(alignment: .top) {
                EventMapView(
                    events: model.events,
                    selectedID: model.selectedID,
                    camera: model.camera,
                    focusToken: model.focusToken,
                    showsUser: location.isAuthorized,
                    reduceMotion: reduceMotion,
                    onSelect: { model.select($0) },
                    onCamera: { model.updateCamera($0) }
                )
                .ignoresSafeArea()
                VStack(spacing: 10) {
                    searchBar(model)
                        .padding(.top, proxy.safeAreaInsets.top + avoid.top + 8)
                        .padding(.leading, 16 + avoid.leading)
                        .padding(.trailing, 16 + avoid.trailing)
                    if location.authorization == .denied || location.authorization == .restricted {
                        locationBanner
                            .padding(.horizontal, 16 + max(avoid.leading, avoid.trailing))
                    }
                    if let error = model.error {
                        Text(error)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NightshiftColor.text)
                            .padding(10)
                            .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            FloatingMapControl(systemImage: "location.fill", label: "Show my location", isActive: location.isAuthorized) {
                                if location.isAuthorized, let current = location.location {
                                    model.center(on: current)
                                } else if location.authorization == .denied {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } else {
                                    location.requestAccess()
                                }
                            }
                            FloatingMapControl(systemImage: "plus", label: "Create a meet") {
                                showCreate = true
                            }
                            .accessibilityIdentifier(UIID.meetsCreate)
                        }
                    }
                    .padding(.trailing, 16 + avoid.trailing)
                    .padding(.bottom, proxy.safeAreaInsets.bottom + avoid.bottom + 12)
                }
            }
        }
        .sheet(item: Binding(
            get: { model.selectedID.map(SelectedEvent.init) },
            set: { model.selectedID = $0?.id }
        )) { selection in
            EventPreviewSheet(eventID: selection.id)
                .presentationDetents([.height(230), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showCreate) {
            EventEditorView(existingID: nil)
        }
    }

    private func searchBar(_ model: MapModel) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NightshiftColor.secondaryText)
                TextField("Search a city or address", text: Bindable(model).query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(UIID.mapSearch)
                    .onSubmit { model.search() }
                if !model.query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        model.query = ""
                        model.suggestions = []
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(NightshiftColor.secondaryText)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onChange(of: model.query) { _, _ in
                model.search()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: model.category == nil && !model.joinedOnly) {
                        model.category = nil
                        model.joinedOnly = false
                        Task { await model.reload() }
                    }
                    FilterChip(title: "Joined", isSelected: model.joinedOnly) {
                        model.joinedOnly.toggle()
                        Task { await model.reload() }
                    }
                    ForEach(EventCategory.allCases) { category in
                        FilterChip(title: category.title, isSelected: model.category == category) {
                            model.category = model.category == category ? nil : category
                            Task { await model.reload() }
                        }
                    }
                }
            }
            if !model.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.suggestions.prefix(5).enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            Task { await model.choose(suggestion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundStyle(NightshiftColor.text)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(NightshiftColor.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var locationBanner: some View {
        Text("Location is off. Search a city to see its meets.")
            .font(.caption.weight(.semibold))
            .foregroundStyle(NightshiftColor.text)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NightshiftColor.elevated.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SelectedEvent: Identifiable, Hashable {
    let id: UUID
}

struct EventMapView: UIViewRepresentable {
    var events: [EventSummary]
    var selectedID: UUID?
    var camera: MapCamera
    var focusToken: UUID
    var showsUser: Bool
    var reduceMotion: Bool
    var onSelect: (UUID) -> Void
    var onCamera: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false
        map.showsUserLocation = showsUser
        map.tintColor = UIColor(hex: 0x00E5FF)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        map.preferredConfiguration = configuration
        map.setRegion(camera.region, animated: false)
        context.coordinator.appliedToken = focusToken
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        map.showsUserLocation = showsUser
        if context.coordinator.appliedToken != focusToken {
            context.coordinator.appliedToken = focusToken
            context.coordinator.isProgrammatic = true
            map.setRegion(camera.region, animated: !reduceMotion)
        }
        context.coordinator.sync(events: events, selectedID: selectedID, on: map, reduceMotion: reduceMotion)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: EventMapView
        var appliedToken: UUID?
        var isProgrammatic = false

        init(_ parent: EventMapView) { self.parent = parent }

        func sync(events: [EventSummary], selectedID: UUID?, on map: MKMapView, reduceMotion: Bool) {
            let existing = map.annotations.compactMap { $0 as? MeetAnnotation }
            let ids = Set(events.map(\.id))
            for annotation in existing where !ids.contains(annotation.eventID) {
                map.removeAnnotation(annotation)
            }
            for event in events {
                if let annotation = existing.first(where: { $0.eventID == event.id }) {
                    annotation.coordinate = event.event.coordinate
                    annotation.category = event.event.category
                    annotation.joined = event.joined
                    annotation.title = event.event.title
                    if let view = map.view(for: annotation) as? EventMarkerView {
                        view.configure(category: event.event.category, joined: event.joined, selected: event.id == selectedID, reduceMotion: reduceMotion, title: event.event.title)
                    }
                } else {
                    map.addAnnotation(MeetAnnotation(event: event))
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cluster") as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "cluster")
                view.annotation = cluster
                view.markerTintColor = UIColor(hex: 0xA020F0)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.glyphTintColor = .white
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                view.displayPriority = .defaultHigh
                view.accessibilityLabel = "\(cluster.memberAnnotations.count) meets"
                return view
            }
            guard let meet = annotation as? MeetAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "meet") as? EventMarkerView
                ?? EventMarkerView(annotation: meet, reuseIdentifier: "meet")
            view.annotation = meet
            view.configure(
                category: meet.category,
                joined: meet.joined,
                selected: meet.eventID == parent.selectedID,
                reduceMotion: parent.reduceMotion,
                title: meet.title ?? "Meet"
            )
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let coordinates = cluster.memberAnnotations.map(\.coordinate)
                mapView.showAnnotations(cluster.memberAnnotations, animated: !parent.reduceMotion)
                mapView.deselectAnnotation(cluster, animated: false)
                _ = coordinates
                return
            }
            guard let meet = view.annotation as? MeetAnnotation else { return }
            parent.onSelect(meet.eventID)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammatic {
                isProgrammatic = false
                return
            }
            parent.onCamera(mapView.region)
        }
    }
}

final class MeetAnnotation: NSObject, MKAnnotation {
    let eventID: UUID
    var category: EventCategory
    var joined: Bool
    var title: String?
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(event: EventSummary) {
        eventID = event.id
        category = event.event.category
        joined = event.joined
        title = event.event.title
        coordinate = event.event.coordinate
    }
}

final class EventMarkerView: MKAnnotationView {
    private let ring = UIView()
    private let dot = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        clusteringIdentifier = "meet"
        canShowCallout = false
        ring.frame = bounds.insetBy(dx: 2, dy: 2)
        ring.layer.cornerRadius = 16
        ring.layer.borderWidth = 2
        addSubview(ring)
        dot.frame = bounds.insetBy(dx: 8, dy: 8)
        dot.contentMode = .scaleAspectFit
        dot.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        addSubview(dot)
        centerOffset = CGPoint(x: 0, y: -8)
    }

    required init?(coder: NSCoder) { nil }

    func configure(category: EventCategory, joined: Bool, selected: Bool, reduceMotion: Bool, title: String) {
        let color: UIColor
        switch category {
        case .show: color = UIColor(hex: 0xFF2D92)
        case .track: color = UIColor(hex: 0x00E5FF)
        default: color = UIColor(hex: 0xA020F0)
        }
        let ringColor = joined ? UIColor(hex: 0x00E5FF) : color
        ring.layer.borderColor = ringColor.cgColor
        ring.backgroundColor = color.withAlphaComponent(0.28)
        dot.tintColor = .white
        dot.image = UIImage(systemName: category.symbol)
        accessibilityLabel = "\(title), \(category.title)"
        displayPriority = selected ? .required : .defaultHigh
        transform = selected ? CGAffineTransform(scaleX: 1.28, y: 1.28) : .identity
        ring.layer.removeAnimation(forKey: "pulse")
        guard selected, !reduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ring.layer.add(pulse, forKey: "pulse")
    }
}
