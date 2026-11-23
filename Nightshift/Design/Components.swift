import SwiftUI
import UIKit

func nightshiftMessage(_ error: Error) -> String {
    if let error = error as? NightshiftError { return error.localizedDescription }
    let text = error.localizedDescription
    if text.localizedCaseInsensitiveContains("offline") || text.localizedCaseInsensitiveContains("network") {
        return "You appear to be offline. Check the connection and try again."
    }
    if text.localizedCaseInsensitiveContains("full") { return "This meet is full." }
    return text.isEmpty ? "Something went wrong." : text
}

struct NeonPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(.white)
            .background(NightshiftColor.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier(identifier ?? title)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(NightshiftColor.text)
            .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NightshiftColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

struct FilterChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : NightshiftColor.secondaryText)
                .background(isSelected ? NightshiftColor.purple : NightshiftColor.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct UserAvatar: View {
    let path: String?
    var name: String
    var size: CGFloat = 44

    var body: some View {
        MediaImage(path: path, thumbnail: true, systemFallback: "person.fill")
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(NightshiftColor.hairline, lineWidth: 1))
            .accessibilityLabel(name)
    }
}

struct StatLabel: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(NightshiftColor.text)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(NightshiftColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(NightshiftColor.secondaryText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NightshiftColor.purple)
            }
        }
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NightshiftColor.purple)
                .frame(width: 76, height: 76)
                .background(NightshiftColor.elevated, in: Circle())
            Text(title)
                .font(NightshiftFont.title(22))
                .foregroundStyle(NightshiftColor.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(NightshiftColor.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                NeonPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingState: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(NightshiftColor.purple)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NightshiftColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorState: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        EmptyState(systemImage: "wifi.exclamationmark", title: "Couldn't load", message: message, actionTitle: "Try again", action: retry)
    }
}

struct NightshiftField: View {
    let title: String
    @Binding var text: String
    var identifier: String?
    var axis: Axis = .horizontal
    var capitalization: TextInputAutocapitalization = .sentences
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(NightshiftColor.secondaryText)
            TextField(title, text: $text, axis: axis)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(capitalization)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .padding(14)
                .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}

struct SecureNightshiftField: View {
    let title: String
    @Binding var text: String
    var identifier: String?
    var contentType: UITextContentType = .password

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(NightshiftColor.secondaryText)
            SecureField(title, text: $text)
                .textFieldStyle(.plain)
                .textContentType(contentType)
                .padding(14)
                .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}

struct FloatingMapControl: View {
    let systemImage: String
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive ? NightshiftColor.cyan : NightshiftColor.text)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(isActive ? NightshiftColor.cyan.opacity(0.8) : NightshiftColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct VehicleSpecificationRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(NightshiftColor.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(NightshiftColor.text)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { NightshiftColor.hairline.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

struct CategoryPill: View {
    let category: EventCategory

    var body: some View {
        Label(category.title, systemImage: category.symbol)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(category.accent)
            .background(category.accent.opacity(0.16), in: Capsule())
    }
}

struct EventCard: View {
    let summary: EventSummary
    var distance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaImage(path: summary.event.coverImagePath, thumbnail: true)
                .frame(height: 168)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    CategoryPill(category: summary.event.category)
                        .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    if summary.joined {
                        Label("Attending", systemImage: "checkmark")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(NightshiftColor.background)
                            .background(NightshiftColor.cyan, in: Capsule())
                            .padding(12)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.event.title)
                    .font(.headline)
                    .foregroundStyle(NightshiftColor.text)
                    .lineLimit(2)
                Text(NightshiftFormat.eventTimeRange(start: summary.event.startsAt, end: summary.event.endsAt))
                    .font(.subheadline)
                    .foregroundStyle(NightshiftColor.secondaryText)
                HStack {
                    Label(summary.event.address, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let distance {
                        Text(distance)
                    }
                }
                .font(.caption)
                .foregroundStyle(NightshiftColor.secondaryText)
                Text("\(summary.attendeeCount) attending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NightshiftColor.text)
            }
            .padding(14)
        }
        .background(NightshiftColor.secondaryBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct VehicleCard: View {
    let summary: VehicleSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaImage(path: summary.coverPath, thumbnail: false)
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.vehicle.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(summary.vehicle.subtitle)
                    .font(.caption)
                    .foregroundStyle(NightshiftColor.secondaryText)
            }
            .padding(12)
        }
        .frame(minHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.vehicle.displayName), \(summary.vehicle.subtitle)")
    }
}

struct GarageHero: View {
    let summary: VehicleSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaImage(path: summary.coverPath, thumbnail: false)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.15), NightshiftColor.background], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.vehicle.nickname?.isEmpty == false ? "BUILD" : "GARAGE")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(NightshiftColor.cyan)
                Text(summary.vehicle.displayName)
                    .font(NightshiftFont.display(34))
                    .foregroundStyle(NightshiftColor.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                Text(summary.vehicle.subtitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NightshiftColor.secondaryText)
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(summary.vehicle.displayName)
    }
}

struct ProfileHeader: View {
    let card: ProfileCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaImage(path: card.profile.coverURL, thumbnail: true, systemFallback: "photo")
                .frame(height: 168)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    UserAvatar(path: card.profile.avatarURL, name: card.profile.displayName, size: 84)
                        .background(Circle().fill(NightshiftColor.background).padding(-4))
                        .offset(y: -28)
                        .padding(.bottom, -28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.profile.displayName)
                            .font(NightshiftFont.title(24))
                            .foregroundStyle(NightshiftColor.text)
                        Text(card.profile.handle)
                            .font(.subheadline)
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    Spacer()
                }
                if !card.profile.bio.isEmpty {
                    Text(card.profile.bio)
                        .font(.body)
                        .foregroundStyle(NightshiftColor.text)
                }
                if card.profile.showCity, let city = card.profile.homeCity, !city.isEmpty {
                    Label(city, systemImage: "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(NightshiftColor.secondaryText)
                }
                Text("Joined \(NightshiftFormat.memberSince(card.profile.createdAt))")
                    .font(.caption)
                    .foregroundStyle(NightshiftColor.secondaryText)
                HStack {
                    StatLabel(value: "\(card.followerCount)", title: "Followers")
                    StatLabel(value: "\(card.followingCount)", title: "Following")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

struct PhotoGallery: View {
    let paths: [String]
    var height: CGFloat = 280

    var body: some View {
        TabView {
            if paths.isEmpty {
                MediaImage(path: nil, thumbnail: false)
                    .frame(height: height)
            } else {
                ForEach(paths, id: \.self) { path in
                    MediaImage(path: path, thumbnail: false)
                        .frame(height: height)
                        .clipped()
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: paths.count > 1 ? .automatic : .never))
        .frame(height: height)
    }
}

struct JoinButton: View {
    let joined: Bool
    var isLoading = false
    var identifier = "event.join"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(joined ? NightshiftColor.cyan : .white)
                } else {
                    Image(systemName: joined ? "checkmark.circle.fill" : "flag.checkered")
                }
                Text(joined ? "Attending" : "Join meet")
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(joined ? NightshiftColor.cyan : Color.white)
            .background(joined ? NightshiftColor.elevated : NightshiftColor.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if joined {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NightshiftColor.cyan.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier(identifier)
        .sensoryFeedback(joined ? .success : .selection, trigger: joined)
        .animation(.spring(duration: 0.25), value: joined)
    }
}

enum UIID {
    static let onboardingNext = "onboarding.next"
    static let onboardingFinish = "onboarding.finish"
    static let email = "auth.email"
    static let password = "auth.password"
    static let username = "auth.username"
    static let displayName = "auth.displayName"
    static let submitAuth = "auth.submit"
    static let toggleAuth = "auth.toggle"
    static let garageAdd = "garage.add"
    static let vehicleMake = "vehicle.make"
    static let vehicleModel = "vehicle.model"
    static let vehicleSave = "vehicle.save"
    static let testPhoto = "useTestPhoto"
    static let meetsCreate = "meets.create"
    static let eventTitle = "event.title"
    static let eventDescription = "event.description"
    static let eventAddress = "event.address"
    static let eventSave = "event.save"
    static let feedCompose = "feed.compose"
    static let postCaption = "post.caption"
    static let postPublish = "post.publish"
    static let postLike = "post.like"
    static let commentField = "comment.field"
    static let commentSend = "comment.send"
    static let settings = "profile.settings"
    static let signOut = "profile.signOut"
    static let mapSearch = "map.search"
}
