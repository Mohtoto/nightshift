import PhotosUI
import SwiftUI

struct GarageScreen: View {
    @Environment(AppModel.self) private var app
    @State private var cars: [VehicleSummary] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showEditor = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && cars.isEmpty {
                    LoadingState(title: "Opening the garage")
                } else if let error, cars.isEmpty {
                    ErrorState(message: error) { Task { await load() } }
                } else if cars.isEmpty {
                    EmptyState(
                        systemImage: "car.fill",
                        title: "Your garage is empty",
                        message: "Add the car you actually drive. Photos, specs, and the parts that make it yours.",
                        actionTitle: "Add a car"
                    ) { showEditor = true }
                } else {
                    gallery
                }
            }
            .navigationTitle("Garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showEditor = true }
                        .accessibilityIdentifier(UIID.garageAdd)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                VehicleDetailView(vehicleID: id)
                    .nightshiftZoomDestination(id: id, in: zoom)
            }
            .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
                VehicleEditorView(existingID: nil) {
                    app.showToast("Added to your garage")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var gallery: some View {
        TabView {
            ForEach(cars) { car in
                NavigationLink(value: car.id) {
                    GarageHero(summary: car)
                        .nightshiftZoomSource(id: car.id, in: zoom)
                }
                .buttonStyle(.plain)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .nightshiftScreen()
    }

    private func load() async {
        guard let id = app.profile?.id else { return }
        do {
            cars = try await app.repository.vehicles(ownerID: id)
            error = nil
        } catch {
            self.error = nightshiftMessage(error)
        }
        isLoading = false
    }
}

struct VehicleDetailView: View {
    let vehicleID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var detail: VehicleDetail?
    @State private var notes: [ConversationNote] = []
    @State private var comment = ""
    @State private var error: String?
    @State private var showEditor = false
    @State private var report = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let detail {
                content(detail)
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                LoadingState(title: "Loading the build")
                    .frame(height: 300)
            }
        }
        .nightshiftScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if detail?.vehicle.ownerID == app.profile?.id {
                        Button("Edit", systemImage: "pencil") { showEditor = true }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                    if let detail {
                        ShareLink(item: "\(detail.vehicle.displayName) — \(detail.vehicle.subtitle) on Nightshift") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Report", systemImage: "flag") { report = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEditor) { VehicleEditorView(existingID: vehicleID) { Task { await load() } } }
        .sheet(isPresented: $report) { ReportSheet(target: .vehicle, targetID: vehicleID) }
        .confirmationDialog("Remove this car?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        }
    }

    @ViewBuilder
    private func content(_ detail: VehicleDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PhotoGallery(paths: detail.photos.map(\.storagePath), height: 320)
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.vehicle.displayName)
                    .font(NightshiftFont.display(34))
                    .foregroundStyle(NightshiftColor.text)
                    .minimumScaleFactor(0.55)
                NavigationLink { ProfileScreen(userID: detail.owner.id) } label: {
                    HStack {
                        UserAvatar(path: detail.owner.avatarURL, name: detail.owner.displayName, size: 36)
                        Text(detail.owner.displayName)
                        Text(detail.owner.handle).foregroundStyle(NightshiftColor.secondaryText)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                if !detail.vehicle.description.isEmpty {
                    Text(detail.vehicle.description)
                        .font(.body)
                        .foregroundStyle(NightshiftColor.text)
                }
                SectionHeader(title: "SPECIFICATION")
                VehicleSpecificationRow(title: "Year", value: "\(detail.vehicle.year)")
                VehicleSpecificationRow(title: "Make", value: detail.vehicle.make)
                VehicleSpecificationRow(title: "Model", value: detail.vehicle.model)
                if let trim = detail.vehicle.trim { VehicleSpecificationRow(title: "Trim", value: trim) }
                if let color = detail.vehicle.color { VehicleSpecificationRow(title: "Color", value: color) }
                if let body = detail.vehicle.bodyStyle { VehicleSpecificationRow(title: "Body", value: body) }
                if let engine = detail.vehicle.engine { VehicleSpecificationRow(title: "Engine", value: engine) }
                if let power = detail.vehicle.power { VehicleSpecificationRow(title: "Power", value: power) }
                if let transmission = detail.vehicle.transmission { VehicleSpecificationRow(title: "Transmission", value: transmission) }
                if !detail.modifications.isEmpty {
                    SectionHeader(title: "MODIFICATIONS")
                    ForEach(detail.modifications) { mod in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mod.category.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(1)
                                .foregroundStyle(NightshiftColor.purple)
                            Text(mod.name).font(.headline)
                            if !mod.description.isEmpty {
                                Text(mod.description).font(.subheadline).foregroundStyle(NightshiftColor.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !detail.attendedMeets.isEmpty {
                    SectionHeader(title: "MEETS ATTENDED")
                    ForEach(detail.attendedMeets) { meet in
                        NavigationLink { EventDetailView(eventID: meet.id) } label: {
                            EventCard(summary: meet)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button {
                        Task { await toggleLike(detail) }
                    } label: {
                        Label("\(detail.likeCount)", systemImage: detail.likedByMe ? "heart.fill" : "heart")
                    }
                    .foregroundStyle(detail.likedByMe ? NightshiftColor.pink : NightshiftColor.text)
                    Spacer()
                    Label("\(detail.commentCount)", systemImage: "bubble.right")
                }
                .font(.headline)
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.author.displayName).font(.subheadline.weight(.semibold))
                        Text(note.content)
                        Text(NightshiftFormat.relative(note.createdAt))
                            .font(.caption)
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    TextField("Comment", text: $comment, axis: .vertical)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier(UIID.commentField)
                    Button("Send") { Task { await sendNote() } }
                        .accessibilityIdentifier(UIID.commentSend)
                }
                .padding(12)
                .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 12))
                if let error {
                    Text(error).foregroundStyle(NightshiftColor.pink)
                }
            }
            .padding(16)
            .foregroundStyle(NightshiftColor.text)
        }
    }

    private func load() async {
        do {
            detail = try await app.repository.vehicle(id: vehicleID)
            notes = try await app.repository.vehicleNotes(id: vehicleID)
            error = nil
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func toggleLike(_ detail: VehicleDetail) async {
        do {
            try await app.repository.setVehicleLike(id: vehicleID, liked: !detail.likedByMe)
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func sendNote() async {
        let text = comment
        do {
            try await app.repository.addVehicleNote(id: vehicleID, content: text)
            comment = ""
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func remove() async {
        do {
            try await app.repository.deleteVehicle(id: vehicleID)
            dismiss()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }
}

struct VehicleEditorView: View {
    let existingID: UUID?
    var onSaved: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = VehicleDraft()
    @State private var message: String?
    @State private var isSaving = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var modCategory = "Exterior"
    @State private var modName = ""
    @State private var modDescription = ""

    private let categories = ["Engine", "Suspension", "Wheels", "Brakes", "Exterior", "Interior", "Exhaust", "Drivetrain", "Other"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    photoStrip
                    NightshiftField(title: "Make", text: $draft.make, identifier: UIID.vehicleMake, capitalization: .words)
                    NightshiftField(title: "Model", text: $draft.model, identifier: UIID.vehicleModel, capitalization: .words)
                    Stepper(value: $draft.year, in: 1900...2100) { Text("Year \(draft.year)") }
                    NightshiftField(title: "Trim", text: $draft.trim)
                    NightshiftField(title: "Nickname", text: $draft.nickname)
                    NightshiftField(title: "Color", text: $draft.color)
                    NightshiftField(title: "Body style", text: $draft.bodyStyle)
                    NightshiftField(title: "Engine", text: $draft.engine)
                    NightshiftField(title: "Power", text: $draft.power)
                    NightshiftField(title: "Transmission", text: $draft.transmission)
                    NightshiftField(title: "Description", text: $draft.description, axis: .vertical)
                    SectionHeader(title: "MODIFICATIONS")
                    ForEach(draft.modifications) { mod in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mod.name).font(.subheadline.weight(.semibold))
                                Text(mod.category).font(.caption).foregroundStyle(NightshiftColor.secondaryText)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                draft.modifications.removeAll { $0.id == mod.id }
                            }
                            .font(.caption)
                        }
                    }
                    Picker("Category", selection: $modCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    NightshiftField(title: "Part", text: $modName)
                    NightshiftField(title: "Notes", text: $modDescription)
                    Button("Add modification") {
                        let name = modName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        draft.modifications.append(ModificationDraft(category: modCategory, name: name, description: modDescription))
                        modName = ""
                        modDescription = ""
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NightshiftColor.purple)
                    if let message {
                        Text(message).foregroundStyle(NightshiftColor.pink)
                    }
                    NeonPrimaryButton(title: existingID == nil ? "Add to garage" : "Save car", isLoading: isSaving, identifier: UIID.vehicleSave) {
                        Task { await save() }
                    }
                }
                .padding(20)
            }
            .nightshiftScreen()
            .navigationTitle(existingID == nil ? "Add a car" : "Edit car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(draft.photos.enumerated()), id: \.element.id) { index, photo in
                        ZStack(alignment: .topTrailing) {
                            photoPreview(photo)
                                .frame(width: 120, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button("Remove", systemImage: "xmark.circle.fill") {
                                draft.photos.removeAll { $0.id == photo.id }
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.white)
                        }
                        if index > 0 {
                            Button("Move up") { draft.photos.swapAt(index, index - 1) }
                                .font(.caption2)
                        }
                    }
                }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                Label("Add photos", systemImage: "photo.on.rectangle")
            }
            .onChange(of: pickerItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            draft.photos.append(PhotoUpload(source: .new(data)))
                        }
                    }
                    pickerItems = []
                }
            }
            if app.uiTesting {
                Button("Use test photo") {
                    draft.photos.append(PhotoUpload(source: .new(TestImages.jpeg(seed: 1))))
                }
                .accessibilityIdentifier(UIID.testPhoto)
            }
            Text("The first photo is the cover.")
                .font(.caption)
                .foregroundStyle(NightshiftColor.secondaryText)
        }
    }

    @ViewBuilder
    private func photoPreview(_ photo: PhotoUpload) -> some View {
        switch photo.source {
        case .existing(let path):
            MediaImage(path: path, thumbnail: true)
        case .new(let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NightshiftColor.elevated
            }
        }
    }

    private func load() async {
        if draft.year == 2020 {
            draft.year = Calendar.current.component(.year, from: Date())
        }
        guard let existingID, let detail = try? await app.repository.vehicle(id: existingID) else { return }
        let vehicle = detail.vehicle
        draft.make = vehicle.make
        draft.model = vehicle.model
        draft.year = vehicle.year
        draft.trim = vehicle.trim ?? ""
        draft.color = vehicle.color ?? ""
        draft.bodyStyle = vehicle.bodyStyle ?? ""
        draft.transmission = vehicle.transmission ?? ""
        draft.engine = vehicle.engine ?? ""
        draft.power = vehicle.power ?? ""
        draft.nickname = vehicle.nickname ?? ""
        draft.description = vehicle.description
        draft.modifications = detail.modifications.map {
            ModificationDraft(id: $0.id, category: $0.category, name: $0.name, description: $0.description)
        }
        draft.photos = detail.photos.map { PhotoUpload(id: $0.id, source: .existing($0.storagePath)) }
    }

    private func save() async {
        if let validation = Validators.vehicle(draft) {
            message = validation
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await app.repository.saveVehicle(draft, existingID: existingID)
            app.images.invalidate()
            onSaved()
            dismiss()
        } catch {
            message = nightshiftMessage(error)
        }
    }
}
