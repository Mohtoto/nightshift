import SwiftUI

struct ReportSheet: View {
    let target: ReportTarget
    let targetID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var alsoBlock = false
    @State private var message: String?
    @State private var isSaving = false

    private let presets = ["Spam", "Harassment", "Dangerous driving", "Inappropriate content"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Reports are stored for moderators. They don't automatically hide someone else's content. You can also block the person.")
                        .font(.subheadline)
                        .foregroundStyle(NightshiftColor.secondaryText)
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) { reason = preset }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(reason == preset ? NightshiftColor.purple : NightshiftColor.text)
                    }
                    NightshiftField(title: "Reason", text: $reason, axis: .vertical)
                    if target == .profile {
                        Toggle("Also block this driver", isOn: $alsoBlock)
                    }
                    if let message { Text(message).foregroundStyle(NightshiftColor.pink) }
                    NeonPrimaryButton(title: "Submit report", isLoading: isSaving) { Task { await submit() } }
                }
                .padding(20)
            }
            .nightshiftScreen()
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        if let validation = Validators.reportReason(reason) {
            message = validation
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.repository.report(target: target, targetID: targetID, reason: reason)
            if alsoBlock, target == .profile {
                try await app.repository.setBlocked(userID: targetID, blocked: true)
            }
            app.showToast("Report sent")
            dismiss()
        } catch {
            message = nightshiftMessage(error)
        }
    }
}
