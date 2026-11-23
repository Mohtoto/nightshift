import Foundation

enum Validators {
    static func username(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            return "Usernames use 3–20 lowercase letters, numbers, or underscores."
        }
        return nil
    }

    static func email(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil else {
            return "Enter a valid email address."
        }
        return nil
    }

    static func password(_ raw: String) -> String? {
        guard raw.count >= 8 else { return "Use at least 8 characters." }
        return nil
    }

    static func displayName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(value.count) else { return "Display names are 1–40 characters." }
        return nil
    }

    static func bio(_ raw: String) -> String? {
        guard raw.count <= 280 else { return "Bios are limited to 280 characters." }
        return nil
    }

    static func vehicle(_ draft: VehicleDraft) -> String? {
        if draft.make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a make." }
        if draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a model." }
        if !(1900...2100).contains(draft.year) { return "Enter a real model year." }
        if draft.photos.isEmpty { return "Add at least one photo." }
        if draft.description.count > 2000 { return "The description is too long." }
        if draft.modifications.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every modification needs a name."
        }
        return nil
    }

    static func event(_ draft: EventDraft, editing: Bool) -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(3...80).contains(title.count) { return "Titles are 3–80 characters." }
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.count < 10 || description.count > 4000 {
            return "Describe the meet in at least 10 characters."
        }
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.count < 3 || address.count > 160 { return "Add a street address." }
        guard let latitude = draft.latitude, let longitude = draft.longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return "Set a location before publishing."
        }
        if latitude == 0 && longitude == 0 { return "Set a location before publishing." }
        if draft.endsAt <= draft.startsAt { return "End time must be after the start time." }
        if !editing && draft.startsAt < Date().addingTimeInterval(-5 * 60) {
            return "Start time must be in the future."
        }
        if draft.limitsCapacity && !(2...5000).contains(draft.capacity) {
            return "Capacity must be between 2 and 5000."
        }
        if draft.coverData == nil && (draft.existingCoverPath?.isEmpty ?? true) {
            return "Add a cover photo."
        }
        return nil
    }

    static func post(caption: String, hasImage: Bool) -> String? {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !hasImage { return "Add a photo or a caption." }
        if trimmed.count > 2000 { return "Captions are limited to 2000 characters." }
        return nil
    }

    static func comment(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2000).contains(trimmed.count) else { return "Comments are 1–2000 characters." }
        return nil
    }

    static func reportReason(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...500).contains(trimmed.count) else { return "Add a short reason, at least 3 characters." }
        return nil
    }
}
