import AVKit
import PhotosUI
import SwiftUI

struct MiraDeliveryView: View {
    let store: MiraStore
    let projectID: UUID
    let media: MiraReelMedia
    let onWords: () -> Void
    let onCheck: () -> Void
    let onWriteNote: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var selection: [PhotosPickerItem] = []
    @State private var preview: MiraReelExport?
    @State private var sharedFile: MiraReelExport?
    @State private var showPreviewAfterJoin = false
    @State private var copied = false
    @State private var savingPhotos = false
    @State private var savedPhotoID: UUID?
    @State private var requestedFix: UUID?
    @State private var phone = ""
    @State private var showWhatsAppFallback = false
    @State private var openingWhatsApp = false

    var body: some View {
        MiraPage {
            if let project = store.project(projectID) {
                if !project.isApproved {
                    MiraApproveFirst(onWords: onWords)
                } else if !project.canFilm {
                    MiraUpdateShots(onWords: onWords)
                } else if let board = project.storyboard, !board.shots.isEmpty {
                    deliveryPage(project, board: board)
                }
            }
        }
        .navigationTitle("Your Reel")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { _, items in importSelection(items) }
        .onChange(of: store.project(projectID)?.currentReelExport) { _, export in
            if showPreviewAfterJoin, let export {
                showPreviewAfterJoin = false
                preview = export
            }
        }
        .fullScreenCover(item: $preview) { export in
            MiraReelPreview(url: media.url(for: export))
        }
        .sheet(item: $sharedFile) { export in
            MiraReelShareSheet(url: media.url(for: export))
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private func deliveryPage(_ project: MiraProject, board: MiraStoryboard) -> some View {
        let join = store.reelJoinState(for: project)
        let post = MiraReelPostState(record: project.deliveryRecord)
        switch post {
        case .posted(let result), .live(let result):
            postedPage(result, state: post, project: project)
        case .ready, .shared:
            switch join {
            case .finished(let export):
                finishedPage(project, export: export, post: post)
            case .rendering:
                MiraTaskHeading(step: .upload)
                ProgressView("Joining your Reel…")
            case .needsClips, .ready, .failed:
                clipsPage(project, board: board, join: join)
            }
        }
    }

    @ViewBuilder private func clipsPage(_ project: MiraProject, board: MiraStoryboard, join: MiraReelJoinState) -> some View {
        let record = project.deliveryRecord
        let match = MiraClipMatchState(record: record, board: board)
        MiraTaskHeading(step: .upload)
        let count = board.shots.filter { project.filmed.contains($0.id) }.count
        if count > 0 { Text(count == 1 ? "1 clip filmed" : "\(count) clips filmed").font(.title2.bold()) }
        if store.deliveryDeal(for: project) == nil {
            let available = store.deals.filter { $0.tracker.postedAt == nil }
            if !available.isEmpty {
                Menu("Link a brand deal") {
                    ForEach(available) { deal in
                        Button(deal.terms.title) { store.linkDeliveryDeal(deal.id, to: projectID) }
                    }
                }
            }
        } else if let deal = store.deliveryDeal(for: project) {
            Text(deal.terms.title).foregroundStyle(.secondary)
        }
        if store.isImportingClips(projectID) {
            ProgressView("Adding your clips…")
        } else {
            let picker = PhotosPicker(
                selection: $selection, maxSelectionCount: 24, selectionBehavior: .ordered,
                matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared()
            ) {
                Text(match.nextAction == .prepareClips ? match.nextAction.title : "Add more clips")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            deliveryButton(picker, prominent: match.nextAction == .prepareClips)
                .accessibilityIdentifier("mira.delivery.add")
            #if DEBUG
            if project.isDemo, MiraDeliveryFixture.isEnabled {
                Button("Add sample clips") { importFixtures(board.id) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("mira.delivery.fixtures")
            }
            #endif
        }
        if !record.clips.isEmpty {
            ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                clipRow(shot, index: index, record: record, boardID: board.id)
            }
        }
        if case .failed(_, let issue) = join { Text(issue).foregroundStyle(.secondary) }
        if match.nextAction == .joinReel {
            Button(join.nextAction == .retry ? "Try joining again" : match.nextAction.title) {
                showPreviewAfterJoin = true
                store.joinReel(projectID) { recipe in try await media.render(recipe) }
            }
            .buttonStyle(MiraPrimaryStyle())
            .disabled(store.isImportingClips(projectID) || project.deliveryRecipe() == nil)
            .accessibilityIdentifier("mira.delivery.join")
        }
        caption(project.deliveryCaption)
    }

    private func clipRow(_ shot: MiraShot, index: Int, record: MiraDelivery, boardID: UUID) -> some View {
        let clipID = record.plans[boardID]?.assignments[shot.id]
        let matched = record.clips.first { $0.id == clipID }
        return MiraFeedCard {
            Text("Shot \(index + 1) · \(shot.editedSeconds) sec").font(.headline)
            Text(shot.purpose)
            if let matched {
                Text(matched.name).accessibilityIdentifier("mira.delivery.clip.\(index + 1)")
                Text("\(matched.seconds.formatted(.number.precision(.fractionLength(1)))) sec")
                    .foregroundStyle(.secondary)
                if matched.seconds + 0.05 < Double(shot.editedSeconds) {
                    Text("This clip is too short. Choose a longer clip.")
                }
            } else {
                Text("No clip yet").foregroundStyle(.secondary)
            }
            Menu(matched == nil ? "Choose clip" : "Swap clip") {
                ForEach(record.clips) { clip in
                    let other = record.plans[boardID]?.assignments.first { $0.value == clip.id && $0.key != shot.id }
                    Button(other == nil ? clip.name : "\(clip.name) · swap") {
                        store.assignClip(clip.id, to: shot.id, in: projectID)
                    }
                }
            }
            .disabled(store.isImportingClips(projectID) || store.isUpdatingDelivery(projectID))
            .accessibilityIdentifier("mira.delivery.swap.\(index + 1)")
        }
    }

    @ViewBuilder private func finishedPage(_ project: MiraProject, export: MiraReelExport, post: MiraReelPostState) -> some View {
        MiraTaskHeading(step: .deliver)
        Button(MiraNextAction.previewReel.title) { preview = export }
            .buttonStyle(.bordered)
        Button(savedPhotoID == export.id ? "Saved to Photos" : "Save to Photos") {
            saveToPhotos(export)
        }
        .buttonStyle(.bordered)
        .disabled(savingPhotos || savedPhotoID == export.id)
        .accessibilityIdentifier("mira.delivery.savePhotos")
        caption(project.deliveryCaption)
        if let deal = store.deliveryDeal(for: project), !deal.terms.checklist.isEmpty {
            let brief = store.deliveryBriefState(for: project, deal: deal)
            briefSection(brief, deal: deal)
            if case .reviewed = brief { shareSection(project, export: export, post: post) }
        } else {
            shareSection(project, export: export, post: post)
        }
        DisclosureGroup("Review clip matches") {
            if let board = project.storyboard {
                ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                    clipRow(shot, index: index, record: project.deliveryRecord, boardID: board.id)
                }
            }
        }
    }

    @ViewBuilder private func briefSection(_ state: MiraDeliveryBriefState, deal: MiraDeal) -> some View {
        MiraSectionTitle(text: "\(deal.terms.title) brief check")
        switch state {
        case .checking:
            ProgressView("Checking the brief…")
        case .reviewed(let review):
            ForEach(deal.terms.checklist) { item in
                if let check = review.checks?.first(where: { $0.id == item.id }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.text).font(.headline)
                        Text(check.status.title).accessibilityIdentifier("mira.delivery.check.\(item.kind.rawValue).\(item.id)")
                        if let text = check.fix?.text, check.status == .canFix {
                            Text(text)
                            Button("Apply this fix") {
                                store.applyDeliveryFix(item.id, to: projectID) { recipe in
                                    try await media.render(recipe)
                                }
                                requestedFix = item.id
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isUpdatingDelivery(projectID))
                            .accessibilityLabel("Apply fix for \(item.text)")
                        }
                        if requestedFix == item.id, check.status == .met {
                            Text(item.requiredText.map { "I added \($0)." } ?? "I added the text.")
                                .accessibilityIdentifier("mira.delivery.adjustment")
                        }
                    }
                }
            }
            if store.isUpdatingDelivery(projectID) {
                ProgressView("Updating your Reel…")
            }
        case .unchecked, .interrupted, .rejected:
            switch state {
            case .interrupted(let review), .rejected(let review):
                if let issue = review.issue { Text(issue).foregroundStyle(.secondary) }
            default: EmptyView()
            }
            Button(state.nextAction.title, action: onCheck)
                .buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.delivery.brief")
        }
    }

    @ViewBuilder private func shareSection(_ project: MiraProject, export: MiraReelExport, post: MiraReelPostState) -> some View {
        if case .shared = post, project.delivery?.sharedExportID == export.id {
            MiraSectionTitle(text: "Did you post it?")
            Button(post.nextAction.title) { store.confirmReelPost(projectID) }
                .buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.delivery.posted")
                .disabled(store.isUpdatingDelivery(projectID))
        }
        let share = Button(MiraNextAction.shareReel.title) {
            UIPasteboard.general.string = project.deliveryCaption
            store.recordReelShare(projectID, exportID: export.id)
            sharedFile = export
        }
        deliveryButton(share, prominent: project.delivery?.sharedExportID != export.id)
            .disabled(store.isUpdatingDelivery(projectID))
            .accessibilityIdentifier("mira.delivery.instagram")
        Text("Mira copies your caption. Choose Instagram in the share sheet, then post in Instagram.")
            .font(.footnote).foregroundStyle(.secondary)
        if project.delivery?.sharedExportID == export.id {
            Button("Open Instagram") {
                openURL(URL(string: "instagram://app")!) { opened in
                    if !opened { store.reportError("Instagram is unavailable. Your Reel is saved in Mira.") }
                }
            }
            .buttonStyle(.bordered)
            Text("If Instagram is missing from the share sheet, save the Reel to Photos and select it in Instagram.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func postedPage(_ result: MiraPostedReel, state: MiraReelPostState, project: MiraProject) -> some View {
        if case .live = state {
            MiraSectionTitle(text: "You're live")
            if let link = result.link { Link("View on Instagram", destination: link) }
        } else {
            MiraSectionTitle(text: "Posted")
            Text("Mira recorded that you posted the Reel.")
        }
        if let deal = store.deliveryDeal(for: project), result.dealID == deal.id {
            if deal.tracker.brandToldAt != nil {
                MiraSectionTitle(text: "Brand told")
            } else {
                noteSection(store.tellBrandState(for: project), deal: deal)
            }
        }
        if let export = project.currentReelExport {
            Button("Watch your Reel") { preview = export }.buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func noteSection(_ state: MiraTellBrandState, deal: MiraDeal) -> some View {
        switch state {
        case .needsNote, .interrupted, .rejected:
            switch state {
            case .interrupted(let note), .rejected(let note):
                if let issue = note.issue { Text(issue).foregroundStyle(.secondary) }
            default: EmptyView()
            }
            Button(state.nextAction.title, action: onWriteNote)
                .buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.delivery.note")
        case .writing:
            ProgressView("Writing your WhatsApp note…")
        case .draft(let note), .opened(let note):
            if let message = note.message {
                MiraSectionTitle(text: "Your WhatsApp note")
                Text(message).textSelection(.enabled).accessibilityIdentifier("mira.delivery.whatsapp.note")
                Button("Copy note") { UIPasteboard.general.string = message }.buttonStyle(.bordered)
                TextField("Brand’s WhatsApp number with country code", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("mira.delivery.whatsapp.phone")
                Button("Send to \(deal.terms.title)") { openWhatsApp(note, message: message) }
                    .buttonStyle(.bordered)
                    .disabled(whatsAppURL(message: message, scheme: "whatsapp") == nil || openingWhatsApp)
                    .accessibilityIdentifier("mira.delivery.whatsapp")
                if showWhatsAppFallback, let url = whatsAppURL(message: message, scheme: "https") {
                    Text("WhatsApp is unavailable. You can copy the note or open this link.")
                    Button("Open WhatsApp link") {
                        openURL(url) { opened in
                            if opened { store.markDeliveryNoteOpened(projectID, jobID: note.job.id) }
                        }
                    }
                    .accessibilityIdentifier("mira.delivery.whatsapp.link")
                    #if DEBUG
                    if MiraDeliveryFixture.isEnabled {
                        Text(url.absoluteString).accessibilityIdentifier("mira.delivery.whatsapp.fixtureURL")
                    }
                    #endif
                }
                if case .opened = state {
                    MiraSectionTitle(text: "Did you send it?")
                    Button(state.nextAction.title) { store.confirmDeliveryNote(projectID) }
                        .buttonStyle(MiraPrimaryStyle())
                        .accessibilityIdentifier("mira.delivery.sent")
                }
            }
        case .sent:
            MiraSectionTitle(text: "Brand told")
        }
    }

    @ViewBuilder private func caption(_ caption: String) -> some View {
        MiraSectionTitle(text: "Your caption")
        if caption.isEmpty {
            Text("No caption yet")
        } else {
            Text(caption).textSelection(.enabled).accessibilityIdentifier("mira.delivery.caption")
            Button(copied ? "Copied" : "Copy caption") {
                UIPasteboard.general.string = caption
                copied = true
            }.buttonStyle(.bordered).accessibilityIdentifier("mira.done.copy")
        }
    }

    private func importSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, let project = store.project(projectID), let board = project.storyboard else { return }
        selection = []
        store.importClips(projectID, board.id) {
            try await media.importClips(items, known: project.deliveryRecord.clips) { issue in store.reportError(issue) }
        }
    }

    #if DEBUG
    private func importFixtures(_ boardID: UUID) {
        store.importClips(projectID, boardID) {
            var clips: [MiraClip] = []
            for name in ["E4FixtureLong", "E4FixtureMedium", "E4FixtureShort"] {
                guard let file = Bundle.main.url(forResource: name, withExtension: "mp4") else {
                    throw MiraError.invalid("The bundled clip is missing.")
                }
                clips.append(try await media.copyClip(file, name: name, sourceID: nil))
            }
            return clips
        }
    }
    #endif

    private func saveToPhotos(_ export: MiraReelExport) {
        savingPhotos = true
        Task {
            defer { savingPhotos = false }
            do {
                try await media.saveToPhotos(export)
                savedPhotoID = export.id
            } catch {
                store.reportError(error.localizedDescription)
            }
        }
    }

    private func openWhatsApp(_ note: MiraBrandMessage, message: String) {
        guard let url = whatsAppURL(message: message, scheme: "whatsapp") else { return }
        openingWhatsApp = true
        openURL(url) { opened in
            openingWhatsApp = false
            showWhatsAppFallback = !opened
            if opened { store.markDeliveryNoteOpened(projectID, jobID: note.job.id) }
        }
    }

    private func whatsAppURL(message: String, scheme: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-")
        guard phone.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let digits = phone.filter { "0123456789".contains($0) }
        guard (7...15).contains(digits.count), digits.first != "0" else { return nil }
        var url = URLComponents()
        url.scheme = scheme
        url.host = scheme == "https" ? "wa.me" : "send"
        url.path = scheme == "https" ? "/\(digits)" : ""
        url.queryItems = (scheme == "https" ? [] : [URLQueryItem(name: "phone", value: digits)])
            + [URLQueryItem(name: "text", value: message)]
        return url.url
    }
}

@ViewBuilder
private func deliveryButton(_ control: some View, prominent: Bool) -> some View {
    if prominent {
        control.buttonStyle(MiraPrimaryStyle())
    } else {
        control.buttonStyle(.bordered)
    }
}

private struct MiraReelPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Reel is ready").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
            .padding(.horizontal)
            VideoPlayer(player: player)
                .accessibilityIdentifier("mira.delivery.player")
        }
        .background(.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task {
            let playback = AVPlayer(url: url)
            player = playback
            playback.play()
        }
        .onDisappear { player?.pause() }
    }
}

private struct MiraReelShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
