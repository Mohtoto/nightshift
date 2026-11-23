import MapKit
import PhotosUI
import SwiftUI

enum MeetWindow: String, CaseIterable, Identifiable {
    case any = "Any time"
    case today = "Today"
    case week = "This week"
    case month = "This month"
    var id: String { rawValue }
}

@MainActor
@Observable
final class MeetsModel {
    var upcoming: [EventSummary] = []
    var nearby: [EventSummary] = []
    var joined: [EventSummary] = []
    var query = ""
    var category: EventCategory?
    var window: MeetWindow = .any
    var isLoading = false
    var error: String?
    private let app: AppModel
    private var searchTask: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var featured: [EventSummary] { upcoming.filter(\.event.category.isFeatured) }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func reload() async {
        isLoading = upcoming.isEmpty && joined.isEmpty
        defer { isLoading = false }
        let now = Date()
        let calendar = Calendar.current
        var startsAfter: Date?
        var startsBefore: Date?
        switch window {
        case .any:
            break
        case .today:
            startsAfter = calendar.startOfDay(for: now)
            startsBefore = calendar.date(byAdding: .day, value: 1, to: startsAfter ?? now)
        case .week:
            startsBefore = calendar.date(byAdding: .day, value: 7, to: now)
        case .month:
            startsBefore = calendar.date(byAdding: .month, value: 1, to: now)
        }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var discover = EventQuery(category: category, search: search.isEmpty ? nil : search, startsAfter: startsAfter, startsBefore: startsBefore, endingAfter: now, limit: 40)
        do {
            upcoming = try await app.repository.events(filter: discover)
            joined = try await app.repository.events(filter: EventQuery(category: category, search: discover.search, joinedOnly: true, limit: 40))
            if let location = app.location.location {
                let box = boundingBox(around: location.coordinate, kilometers: 80)
                discover.south = box.south
                discover.north = box.north
                discover.west = box.west
                discover.east = box.east
                let rows = try await app.repository.events(filter: discover)
                nearby = rows.sorted {
                    distance($0, from: location) < distance($1, from: location)
                }
            } else {
                nearby = []
            }
            error = nil
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    func distanceText(for summary: EventSummary) -> String? {
        guard let location = app.location.location else { return nil }
        return NightshiftFormat.distance(distance(summary, from: location))
    }

    private func distance(_ summary: EventSummary, from location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: summary.event.latitude, longitude: summary.event.longitude))
    }

    private func boundingBox(around coordinate: CLLocationCoordinate2D, kilometers: Double) -> (south: Double, north: Double, west: Double, east: Double) {
        let lat = kilometers / 111
        let lon = kilometers / max(111 * cos(coordinate.latitude * .pi / 180), 0.2)
        return (coordinate.latitude - lat, coordinate.latitude + lat, coordinate.longitude - lon, coordinate.longitude + lon)
    }
}

struct MeetsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LocationService.self) private var location
    @State private var model: MeetsModel?
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    LoadingState(title: "Loading meets")
                }
            }
            .navigationTitle("Meets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create", systemImage: "plus") { showCreate = true }
                        .accessibilityIdentifier(UIID.meetsCreate)
                }
            }
            .sheet(isPresented: $showCreate) {
                EventEditorView(existingID: nil)
            }
            .navigationDestination(for: UUID.self) { id in
                EventDetailView(eventID: id)
            }
        }
        .task {
            let active: MeetsModel
            if let model {
                active = model
            } else {
                let created = MeetsModel(app: app)
                model = created
                active = created
            }
            if location.authorization == .notDetermined {
                location.requestAccess()
            }
            await active.reload()
            for await signal in app.repository.changes() {
                if signal == .events { await active.reload() }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: MeetsModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                chipRow(model)
                if model.isLoading && model.upcoming.isEmpty {
                    LoadingState(title: "Looking for meets")
                        .frame(height: 220)
                } else if let error = model.error, model.upcoming.isEmpty {
                    ErrorState(message: error) { Task { await model.reload() } }
                        .frame(height: 280)
                } else if model.upcoming.isEmpty && model.joined.isEmpty {
                    EmptyState(
                        systemImage: "flag.checkered",
                        title: "No meets yet",
                        message: "Be the first to put a lawful meet on the map.",
                        actionTitle: "Create a meet"
                    ) { showCreate = true }
                    .frame(height: 320)
                } else {
                    if !model.featured.isEmpty {
                        section("Featured", events: model.featured, model: model, horizontal: true)
                    }
                    if !model.nearby.isEmpty {
                        section("Nearby", events: model.nearby, model: model)
                    } else if location.authorization == .denied {
                        Text("Turn on location to sort meets by distance, or keep browsing upcoming ones.")
                            .font(.subheadline)
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    if !model.joined.isEmpty {
                        section("You're going", events: model.joined, model: model)
                    }
                    section("Upcoming", events: model.upcoming, model: model)
                }
            }
            .padding(.vertical, 12)
        }
        .nightshiftScreen()
        .searchable(text: Bindable(model).query, prompt: "Search meets")
        .onChange(of: model.query) { _, _ in model.scheduleSearch() }
        .refreshable { await model.reload() }
    }

    private func chipRow(_ model: MeetsModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: model.category == nil) {
                        model.category = nil
                        Task { await model.reload() }
                    }
                    ForEach(EventCategory.allCases) { category in
                        FilterChip(title: category.title, isSelected: model.category == category) {
                            model.category = model.category == category ? nil : category
                            Task { await model.reload() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MeetWindow.allCases) { window in
                        FilterChip(title: window.rawValue, isSelected: model.window == window) {
                            model.window = window
                            Task { await model.reload() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func section(_ title: String, events: [EventSummary], model: MeetsModel, horizontal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title.uppercased())
                .padding(.horizontal, 16)
            if horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(events) { event in
                            NavigationLink(value: event.id) {
                                EventCard(summary: event, distance: model.distanceText(for: event))
                                    .frame(width: 280)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(events) { event in
                        NavigationLink(value: event.id) {
                            EventCard(summary: event, distance: model.distanceText(for: event))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct EventPreviewSheet: View {
    let eventID: UUID
    @Environment(AppModel.self) private var app
    @State private var detail: EventDetail?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            preview
        }
        .presentationDetents([.height(280), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let detail {
                HStack(alignment: .top, spacing: 12) {
                    MediaImage(path: detail.event.coverImagePath, thumbnail: true)
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.event.title)
                            .font(.headline)
                            .foregroundStyle(NightshiftColor.text)
                            .lineLimit(2)
                        Text(NightshiftFormat.eventDay(detail.event.startsAt))
                            .font(.subheadline)
                            .foregroundStyle(NightshiftColor.secondaryText)
                        Text(detail.event.address)
                            .font(.caption)
                            .foregroundStyle(NightshiftColor.secondaryText)
                            .lineLimit(2)
                        Text("\(detail.attendeeCount) attending")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NightshiftColor.text)
                    }
                }
                NavigationLink {
                    EventDetailView(eventID: detail.id)
                } label: {
                    Text(detail.joined ? "View meet" : "View and join")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .foregroundStyle(.white)
                        .background(NightshiftColor.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if let error {
                Text(error).foregroundStyle(NightshiftColor.pink)
            } else {
                LoadingState(title: "Loading meet")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NightshiftColor.secondaryBackground)
        .task { await load() }
    }

    private func load() async {
        do { detail = try await app.repository.event(id: eventID) }
        catch { self.error = nightshiftMessage(error) }
    }
}

struct EventDetailView: View {
    let eventID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var detail: EventDetail?
    @State private var error: String?
    @State private var isWorking = false
    @State private var showVehicles = false
    @State private var showEditor = false
    @State private var report = false
    @State private var vehicles: [VehicleSummary] = []

    var body: some View {
        ScrollView {
            if let detail {
                loaded(detail)
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
                    .frame(height: 320)
            } else {
                LoadingState(title: "Loading meet")
                    .frame(height: 320)
            }
        }
        .nightshiftScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail, detail.event.hostID == app.profile?.id {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") { showEditor = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let detail {
                        ShareLink(item: shareText(detail)) { Label("Share", systemImage: "square.and.arrow.up") }
                        Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") { openDirections(detail) }
                    }
                    Button("Report", systemImage: "flag") { report = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEditor) {
            EventEditorView(existingID: eventID)
        }
        .sheet(isPresented: $report) {
            ReportSheet(target: .event, targetID: eventID)
        }
        .confirmationDialog("Bring a car?", isPresented: $showVehicles, titleVisibility: .visible) {
            Button("Join without a car") { Task { await join(vehicleID: nil) } }
            ForEach(vehicles) { vehicle in
                Button(vehicle.vehicle.displayName) { Task { await join(vehicleID: vehicle.id) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func loaded(_ detail: EventDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MediaImage(path: detail.event.coverImagePath, thumbnail: false)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 14) {
                CategoryPill(category: detail.event.category)
                Text(detail.event.title)
                    .font(NightshiftFont.display(32))
                    .foregroundStyle(NightshiftColor.text)
                    .minimumScaleFactor(0.6)
                NavigationLink {
                    ProfileScreen(userID: detail.host.id)
                } label: {
                    HStack(spacing: 10) {
                        UserAvatar(path: detail.host.avatarURL, name: detail.host.displayName, size: 40)
                        VStack(alignment: .leading) {
                            Text(detail.host.displayName).foregroundStyle(NightshiftColor.text)
                            Text("Host · \(detail.host.handle)").font(.caption).foregroundStyle(NightshiftColor.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                Label(NightshiftFormat.eventTimeRange(start: detail.event.startsAt, end: detail.event.endsAt), systemImage: "calendar")
                Label(detail.event.address, systemImage: "mappin.and.ellipse")
                Label(detail.event.visibility == .public ? "Public" : "Unlisted", systemImage: "eye")
                if detail.event.status == .cancelled {
                    Text("This meet was cancelled.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NightshiftColor.pink)
                }
                Map(position: .constant(.region(MKCoordinateRegion(center: detail.event.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))))) {
                    Marker(detail.event.title, coordinate: detail.event.coordinate)
                        .tint(detail.event.category == .show ? NightshiftColor.pink : NightshiftColor.purple)
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)
                Text(detail.event.description)
                    .font(.body)
                    .foregroundStyle(NightshiftColor.text)
                if !detail.event.rules.isEmpty {
                    SectionHeader(title: "RULES")
                    Text(detail.event.rules)
                        .font(.body)
                        .foregroundStyle(NightshiftColor.secondaryText)
                }
                SectionHeader(title: "ATTENDING", trailing: "\(detail.attendeeCount)")
                if detail.attendees.isEmpty {
                    Text("Nobody has joined yet.")
                        .foregroundStyle(NightshiftColor.secondaryText)
                } else {
                    ForEach(detail.attendees) { attendee in
                        HStack(spacing: 10) {
                            UserAvatar(path: attendee.profile.avatarURL, name: attendee.profile.displayName, size: 36)
                            VStack(alignment: .leading) {
                                Text(attendee.profile.displayName)
                                if let vehicle = attendee.vehicle {
                                    Text(vehicle.displayName).font(.caption).foregroundStyle(NightshiftColor.secondaryText)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(NightshiftColor.pink)
                }
                if detail.event.status == .scheduled {
                    JoinButton(joined: detail.joined, isLoading: isWorking) {
                        if detail.joined {
                            Task { await leave() }
                        } else {
                            Task { await prepareJoin() }
                        }
                    }
                }
                if detail.event.hostID == app.profile?.id && detail.event.status == .scheduled {
                    Button("Cancel meet", role: .destructive) { Task { await cancel() } }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .foregroundStyle(NightshiftColor.secondaryText)
        }
    }

    private func load() async {
        do {
            detail = try await app.repository.event(id: eventID)
            if let id = app.profile?.id {
                vehicles = try await app.repository.vehicles(ownerID: id)
            }
            error = nil
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func prepareJoin() async {
        if vehicles.isEmpty {
            await join(vehicleID: nil)
        } else {
            showVehicles = true
        }
    }

    private func join(vehicleID: UUID?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await app.repository.joinEvent(id: eventID, vehicleID: vehicleID)
            app.showToast("You're on the list")
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func leave() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await app.repository.leaveEvent(id: eventID)
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func cancel() async {
        do {
            try await app.repository.cancelEvent(id: eventID)
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func shareText(_ detail: EventDetail) -> String {
        "\(detail.event.title) · \(NightshiftFormat.eventTimeRange(start: detail.event.startsAt, end: detail.event.endsAt)) · \(detail.event.address)"
    }

    private func openDirections(_ detail: EventDetail) {
        let coordinate = detail.event.coordinate
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = detail.event.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

struct EventEditorView: View {
    let existingID: UUID?
    @Environment(AppModel.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var draft = EventDraft()
    @State private var message: String?
    @State private var isSaving = false
    @State private var search = ""
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nightshift is for lawful meets, shows, cruises, and organized track days.")
                        .font(.footnote)
                        .foregroundStyle(NightshiftColor.secondaryText)
                    cover
                    NightshiftField(title: "Title", text: $draft.title, identifier: UIID.eventTitle)
                    NightshiftField(title: "Description", text: $draft.description, identifier: UIID.eventDescription, axis: .vertical)
                    NightshiftField(title: "Rules", text: $draft.rules, axis: .vertical)
                    Picker("Category", selection: $draft.category) {
                        ForEach(EventCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Visibility", selection: $draft.visibility) {
                        ForEach(EventVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Starts", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                    Toggle("Limit attendees", isOn: $draft.limitsCapacity)
                    if draft.limitsCapacity {
                        Stepper(value: $draft.capacity, in: 2...5000) {
                            Text("Capacity \(draft.capacity)")
                        }
                    }
                    NightshiftField(title: "Address", text: $draft.address, identifier: UIID.eventAddress)
                    HStack {
                        TextField("Search address", text: $search)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 12))
                        Button("Find") { Task { await findAddress() } }
                            .font(.subheadline.weight(.semibold))
                    }
                    Button("Use my location") { Task { await useMyLocation() } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NightshiftColor.cyan)
                    if app.uiTesting {
                        Button("Use test location") {
                            draft.latitude = 34.0522
                            draft.longitude = -118.2437
                            draft.address = "1 Sunset Blvd, Los Angeles"
                        }
                        .accessibilityIdentifier("useTestLocation")
                    }
                    if let latitude = draft.latitude, let longitude = draft.longitude {
                        Text(String(format: "%.4f, %.4f", latitude, longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    if let message {
                        Text(message).font(.subheadline).foregroundStyle(NightshiftColor.pink)
                    }
                    NeonPrimaryButton(title: existingID == nil ? "Publish meet" : "Save changes", isLoading: isSaving, identifier: UIID.eventSave) {
                        Task { await save() }
                    }
                }
                .padding(20)
            }
            .nightshiftScreen()
            .navigationTitle(existingID == nil ? "New meet" : "Edit meet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await loadExisting() }
        }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.coverData != nil || draft.existingCoverPath != nil {
                Group {
                    if let data = draft.coverData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        MediaImage(path: draft.existingCoverPath, thumbnail: false)
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Cover photo", systemImage: "photo")
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        draft.coverData = data
                    }
                }
            }
            if app.uiTesting {
                Button("Use test photo") { draft.coverData = TestImages.jpeg(seed: 2) }
                    .accessibilityIdentifier(UIID.testPhoto)
            }
        }
    }

    private func loadExisting() async {
        guard let existingID else {
            let start = Date().addingTimeInterval(60 * 60 * 24)
            if draft.startsAt == Date(timeIntervalSince1970: 0) {
                draft.startsAt = start
                draft.endsAt = start.addingTimeInterval(60 * 60 * 3)
            }
            return
        }
        guard let detail = try? await app.repository.event(id: existingID) else { return }
        draft.title = detail.event.title
        draft.description = detail.event.description
        draft.rules = detail.event.rules
        draft.address = detail.event.address
        draft.latitude = detail.event.latitude
        draft.longitude = detail.event.longitude
        draft.startsAt = detail.event.startsAt
        draft.endsAt = detail.event.endsAt
        draft.category = detail.event.category
        draft.visibility = detail.event.visibility
        draft.limitsCapacity = detail.event.capacity != nil
        draft.capacity = detail.event.capacity ?? 50
        draft.existingCoverPath = detail.event.coverImagePath
    }

    private func findAddress() async {
        do {
            let place = try await PlaceSearch.search(query: search.isEmpty ? draft.address : search)
            draft.address = place.address
            draft.latitude = place.coordinate.latitude
            draft.longitude = place.coordinate.longitude
            message = nil
        } catch {
            message = nightshiftMessage(error)
        }
    }

    private func useMyLocation() async {
        if location.authorization == .notDetermined { location.requestAccess() }
        location.refresh()
        guard let current = location.location else {
            message = "Location isn't available yet."
            return
        }
        do {
            draft.latitude = current.coordinate.latitude
            draft.longitude = current.coordinate.longitude
            draft.address = try await PlaceSearch.address(at: current.coordinate)
        } catch {
            message = nightshiftMessage(error)
        }
    }

    private func save() async {
        if let validation = Validators.event(draft, editing: existingID != nil) {
            message = validation
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await app.repository.saveEvent(draft, existingID: existingID)
            app.images.invalidate()
            app.showToast(existingID == nil ? "Meet is live" : "Meet updated")
            dismiss()
        } catch {
            message = nightshiftMessage(error)
        }
    }
}
