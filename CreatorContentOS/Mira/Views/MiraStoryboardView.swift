import SwiftUI

extension EnvironmentValues {
    @Entry var miraPictureUnavailable: (UUID, UUID, UUID, URL) -> Void = { _, _, _, _ in }
}

struct MiraStoryboardView: View {
    var store: MiraStore
    var projectID: UUID
    var tab: MiraMainTab
    var onUpdate: () -> Void
    var body: some View {
        if let project = store.project(projectID), let board = project.storyboard {
            VStack(alignment: .leading, spacing: 20) {
                MiraSectionTitle(text: "Your filming plan")
                Text(
                    "About \(board.shots.reduce(0){$0+$1.editedSeconds}) seconds edited · \(board.shots.count) shots"
                ).font(.headline)
                let locations = details(board.shots.map(\.location))
                let props = details(board.shots.map(\.props))
                MiraShotRow(title: "Where", icon: "location", value: locations.isEmpty ? project.constraints.location : locations)
                MiraShotRow(title: "What to bring", icon: "bag", value: props.isEmpty ? project.constraints.equipment : props)
                MiraShotRow(title: "Audio", icon: "mic", value: audio(board.shots))
                if project.shotsNeedUpdate {
                    Text("Mira needs to update the shots").font(.headline)
                }
                if !project.canFilm {
                    MiraInlineAction { mainAction(project) }
                }
                ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Shot \(index + 1)").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        MiraShotPicture(
                            shot: shot, number: index + 1,
                            picture: store.picture(in: project, boardID: board.id, shotID: shot.id),
                            source: (project.id, board.id))
                        Text(shot.purpose).font(.title3.weight(.semibold))
                        if project.needsReview.contains(shot.id) {
                            Text("Changed shot · review before filming").font(.headline)
                        }
                        if project.filmed.contains(shot.id) {
                            Label("Filmed by you", systemImage: "checkmark.circle").font(.headline)
                        }
                        Divider()
                        MiraShotRow(title: "Phone position", icon: "iphone", value: shot.placement)
                        MiraShotRow(title: "Distance", icon: "ruler", value: shot.distance)
                        MiraShotRow(title: "Framing", icon: "viewfinder", value: shot.framing)
                        MiraShotRow(
                            title: "Seconds", icon: "clock",
                            value: "\(shot.editedSeconds) seconds in the final video")
                        MiraShotRow(title: "Words to say", icon: "mic", value: shot.words)
                        if shot.voiceover && !shot.words.isEmpty {
                            Text("Record these words separately.").font(.title3)
                        }
                        MiraShotRow(title: "On-screen text", icon: "textformat", value: shot.onScreenText)
                        MiraShotRow(title: "Where", icon: "location", value: shot.location)
                        if !shot.props.isEmpty {
                            MiraShotRow(title: "What you need", icon: "bag", value: shot.props)
                        }
                        Text("Record for about \(shot.recordingSeconds) seconds.")
                        Text(shot.action)
                        if !shot.simplerAlternative.isEmpty {
                            Text("Simpler option: \(shot.simplerAlternative)")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.18)))
                    .foregroundStyle(.primary)
                }
                if !board.mappings.isEmpty {
                    MiraSectionTitle(text: "Brand requirements included in the plan")
                    ForEach(project.brief.requirements) { requirement in
                        let mapping = board.mappings.first { $0.requirementID == requirement.id }
                        Text("\(requirement.kind): \(requirement.value)").font(.headline)
                        if let mapping {
                            if !mapping.scriptExcerpt.isEmpty { Text("Script: \(mapping.scriptExcerpt)") }
                            Text(
                                "Shots: \(mapping.shotIDs.compactMap{id in board.shots.firstIndex{$0.id==id}.map{String($0+1)}}.joined(separator:", "))"
                            )
                        } else {
                            Text("Not mapped · needs review")
                        }
                    }
                } else if case .confirmed = project.briefState {
                    Text("Brand requirements confirmed").font(.headline)
                }
                if project.canFilm {
                    MiraInlineAction { mainAction(project) }
                }
            }
        }
    }

    @ViewBuilder func mainAction(_ project: MiraProject) -> some View {
        if project.shotsNeedUpdate {
            Button("Update shot list", action: onUpdate).buttonStyle(MiraPrimaryStyle())
                .disabled(project.isApproved && store.requestState(project.job).pending)
        } else if !project.isApproved {
            NavigationLink(value: MiraRoute.words(projectID)) {
                Text("Approve your words").frame(maxWidth: .infinity, minHeight: 52)
            }.buttonStyle(MiraPrimaryStyle()).accessibilityIdentifier("mira.shots.approve")
        } else if project.canFilm {
            let step = store.taskStep(.editor(projectID), in: project, tab: tab)
            NavigationLink(value: MiraRoute.shooting(projectID)) {
                Text(step.nextAction.title)
            }.buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.shots.film")
        }
    }

    private func details(_ values: [String]) -> String {
        var seen: Set<String> = []
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: " · ")
    }

    private func audio(_ shots: [MiraShot]) -> String {
        let spoken = shots.filter { !$0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if spoken.isEmpty { return "No words to record." }
        if !spoken.contains(where: { $0.voiceover }) { return "Speak while you film." }
        if spoken.allSatisfy({ $0.voiceover }) { return "Record the voiceover separately." }
        return "Speak while you film. Record marked voiceovers separately."
    }
}
private struct MiraShotRow: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(title)
            }.font(.title3.bold())
            Text(value.isEmpty ? "None" : value).font(.title3)
        }
    }
}
struct MiraShotDetails: View {
    var shot: MiraShot
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phone position").font(.headline)
            Text(shot.placement)
            if !shot.distance.isEmpty {
                Text("Distance").font(.headline)
                Text(shot.distance)
            }
            if !shot.framing.isEmpty {
                Text("Framing").font(.headline)
                Text(shot.framing)
            }
            Text("What to do").font(.headline)
            Text(shot.action)
            if !shot.words.isEmpty {
                Text(shot.voiceover ? "Voiceover · record separately" : "Say to camera").font(.headline)
                Text(shot.words).textSelection(.enabled)
            }
            if !shot.onScreenText.isEmpty {
                Text("On-screen text").font(.headline)
                Text(shot.onScreenText)
            }
            if !shot.simplerAlternative.isEmpty {
                Text("Simpler option").font(.headline)
                Text(shot.simplerAlternative)
            }
        }.padding(.vertical, 16)
    }
}
struct MiraShootingView: View {
    var store: MiraStore
    var projectID: UUID
    var tab: MiraMainTab
    var onAsk: (UUID) -> Void
    var onDone: () -> Void
    var onWords: () -> Void
    var body: some View {
        MiraPage {
            if let project = store.project(projectID), !project.isApproved {
                MiraApproveFirst(onWords: onWords)
            } else if let project = store.project(projectID), !project.canFilm {
                MiraUpdateShots(onWords: onWords)
            } else if let project = store.project(projectID), let board = project.storyboard,
                !board.shots.isEmpty
            {
                let index = min(max(0, project.shotIndex), board.shots.count - 1)
                let shot = board.shots[index]
                let step = store.taskStep(.filming(projectID), in: project)
                MiraTaskHeading(step: step)
                Text("Shot \(index+1) of \(board.shots.count)").font(.title2)
                Text("\(board.shots.filter{project.filmed.contains($0.id)}.count) filmed by you").font(
                    .callout)
                MiraShotPicture(
                    shot: shot, number: index + 1,
                    picture: store.picture(in: project, boardID: board.id, shotID: shot.id),
                    source: (project.id, board.id))
                Text(index == 0 ? "Say your opening line" : (index == board.shots.count - 1 ? "Say your last line" : "Say the next part"))
                    .font(.title.bold())
                Text("Film for about \(shot.recordingSeconds) seconds").monospacedDigit()
                MiraShotDetails(shot: shot)
                if project.needsReview.contains(shot.id) {
                    Text("This shot changed. Check these instructions before filming again.").font(.headline)
                }
                let mark = Button(
                    project.filmed.contains(shot.id)
                        ? "Mark not filmed"
                        : (project.needsReview.contains(shot.id) ? "Reviewed and filmed" : MiraNextAction.markFilmed.title)
                ) {
                    store.toggleFilmed(projectID, shotID: shot.id)
                }
                if project.stage == .complete {
                    mark.buttonStyle(.bordered)
                } else {
                    mark.buttonStyle(MiraPrimaryStyle())
                }
                HStack {
                    Button("Previous") { move(max(0, index - 1)) }.disabled(index == 0)
                    Spacer()
                    Button("Next") { move(min(board.shots.count - 1, index + 1)) }.disabled(
                        index == board.shots.count - 1)
                }.buttonStyle(.bordered)
                Button("Make this easier") { onAsk(shot.id) }
                Text("Mira does not record or analyse footage. Filmed is progress you report yourself.")
                    .font(
                        .footnote
                    ).foregroundStyle(.secondary)
                if project.stage == .complete {
                    Button(step.nextAction.title, action: onDone).buttonStyle(MiraPrimaryStyle())
                        .accessibilityIdentifier("mira.filming.finish")
                }
            } else {
                Text("Make a shot list before filming.")
            }
        }.navigationTitle("Filming").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                store.startFilming(projectID, tab: tab)
            }
    }
    private func move(_ index: Int) {
        store.moveShot(projectID, to: index)
    }
}

struct MiraApproveFirst: View {
    var onWords: () -> Void
    var body: some View {
        Text("Your words changed. Approve them first.").font(.title2.bold())
            .accessibilityIdentifier("mira.approveFirst.message")
        Button("Approve your words", action: onWords).buttonStyle(MiraPrimaryStyle())
            .accessibilityIdentifier("mira.approveFirst.words")
    }
}

private struct MiraUpdateShots: View {
    var onWords: () -> Void
    var body: some View {
        Text("Mira needs to update the shots").font(.title2.bold())
        Button("Update shot list", action: onWords).buttonStyle(MiraPrimaryStyle())
    }
}

struct MiraDoneView: View {
    var store: MiraStore
    var projectID: UUID
    var onWords: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    var body: some View {
        MiraPage {
            if let project = store.project(projectID), !project.isApproved {
                MiraApproveFirst(onWords: onWords)
            } else if let project = store.project(projectID), !project.canFilm {
                MiraUpdateShots(onWords: onWords)
            } else if let project = store.project(projectID), let board = project.storyboard,
                !board.shots.isEmpty
            {
                let count = board.shots.filter { project.filmed.contains($0.id) }.count
                let caption = project.script?.caption.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                MiraTaskHeading(step: store.taskStep(.done(projectID), in: project))
                Text("Upload and post in Mira are later steps.").foregroundStyle(.secondary)
                Text(count == 1 ? "1 clip filmed" : "\(count) clips filmed")
                    .font(.largeTitle.bold()).monospacedDigit()
                MiraSectionTitle(text: "Your caption")
                if caption.isEmpty {
                    Text("No caption yet").font(.title3)
                } else {
                    Text(caption).font(.title3).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy caption") {
                        UIPasteboard.general.string = caption
                        copied = true
                    }.buttonStyle(.bordered).accessibilityIdentifier("mira.done.copy")
                        .sensoryFeedback(.success, trigger: copied)
                }
                MiraSectionTitle(text: "Clip order")
                ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)").font(.title3.bold()).monospacedDigit()
                        Text(line(shot, index)).font(.title3)
                        Spacer(minLength: 8)
                        if project.filmed.contains(shot.id) {
                            Image(systemName: "checkmark.circle.fill").font(.title3)
                                .accessibilityLabel("Filmed")
                        }
                    }
                }
                Button(MiraNextAction.prepareClips.title) {
                    openURL(URL(string: "instagram://app")!) { accepted in
                        if !accepted {
                            openURL(URL(string: "https://apps.apple.com/app/instagram/id389801252")!)
                        }
                    }
                }.buttonStyle(MiraPrimaryStyle()).accessibilityIdentifier("mira.done.instagram")
                Text("Mira does not post. You post in Instagram.").font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Make a shot list before filming.")
            }
        }.navigationTitle("Done").navigationBarTitleDisplayMode(.inline)
    }
    private func line(_ shot: MiraShot, _ index: Int) -> String {
        if !shot.words.isEmpty { return shot.words }
        if !shot.onScreenText.isEmpty { return shot.onScreenText }
        return "Shot \(index + 1)"
    }
}

struct MiraShotPicture: View {
    let shot: MiraShot
    let number: Int
    var showSeconds = false
    var picture: MiraShotPictureState? = nil
    var source: (project: UUID, board: UUID)? = nil
    @Environment(\.miraPictureUnavailable) private var pictureUnavailable
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth = 49.0

    var body: some View {
        let width = showSeconds ? min(thumbnailWidth, 68) : 88
        VStack(spacing: 5) {
            Group {
                switch picture {
                case .ready(let url, _):
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                                .accessibilityLabel("AI picture for shot \(number)")
                        case .failure:
                            drawing.onAppear {
                                if let source { pictureUnavailable(source.project, source.board, shot.id, url) }
                            }
                        default: drawing
                        }
                    }
                    .id(url)
                case .pending, .refreshing, .failed, nil: drawing
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(.rect(cornerRadius: 8))
            if showSeconds { Text("\(shot.editedSeconds)s").font(.body.monospacedDigit()) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot \(number), \(shot.pictureType.label), \(shot.editedSeconds) seconds")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("mira.shot.picture.\(number)")
    }

    private var drawing: some View {
        Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let phone = Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: size.width * 0.17)
                context.fill(phone, with: .color(MiraTheme.paper))
                context.stroke(phone, with: .color(MiraTheme.ink), lineWidth: 2)
                let lens = CGRect(x: size.width * 0.44, y: size.height * 0.08,
                                  width: size.width * 0.12, height: 2)
                context.fill(Path(roundedRect: lens, cornerRadius: 1), with: .color(MiraTheme.ink))
                let screen = CGRect(x: size.width * 0.14, y: size.height * 0.17,
                                    width: size.width * 0.72, height: size.height * 0.73)
                context.clip(to: Path(roundedRect: screen, cornerRadius: 4))
                let transform = CGAffineTransform(a: screen.width / 100, b: 0, c: 0, d: screen.height / 140,
                                                  tx: screen.minX, ty: screen.minY)
                context.stroke(figure.applying(transform), with: .color(MiraTheme.ink),
                               style: StrokeStyle(lineWidth: max(1.7, size.width * 0.035),
                                                  lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Drawn frame for shot \(number)")
        .accessibilityAddTraits(.isImage)
    }

    private var figure: Path {
        Path { path in
            func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                path.addEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
            func line(_ points: CGPoint...) {
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            func shoulders(_ y: CGFloat, _ bottom: CGFloat) {
                path.move(to: CGPoint(x: 17, y: bottom))
                path.addQuadCurve(to: CGPoint(x: 50, y: y), control: CGPoint(x: 18, y: y))
                path.addQuadCurve(to: CGPoint(x: 83, y: bottom), control: CGPoint(x: 82, y: y))
            }
            switch shot.pictureType {
            case .face:
                oval(14, 20, 72, 92)
                line(CGPoint(x: 33, y: 54), CGPoint(x: 39, y: 54))
                line(CGPoint(x: 61, y: 54), CGPoint(x: 67, y: 54))
                path.move(to: CGPoint(x: 38, y: 79))
                path.addQuadCurve(to: CGPoint(x: 62, y: 79), control: CGPoint(x: 50, y: 94))
            case .headShoulders:
                oval(28, 15, 44, 55)
                shoulders(78, 137)
            case .halfBody:
                oval(34, 10, 32, 39)
                shoulders(57, 115)
                line(CGPoint(x: 31, y: 90), CGPoint(x: 31, y: 120), CGPoint(x: 69, y: 120), CGPoint(x: 69, y: 90))
            case .fullBody:
                oval(39, 7, 22, 26)
                line(CGPoint(x: 50, y: 36), CGPoint(x: 50, y: 82))
                line(CGPoint(x: 25, y: 70), CGPoint(x: 50, y: 45), CGPoint(x: 75, y: 70))
                line(CGPoint(x: 29, y: 126), CGPoint(x: 50, y: 82), CGPoint(x: 71, y: 126))
            case .side:
                path.move(to: CGPoint(x: 39, y: 80))
                path.addCurve(to: CGPoint(x: 63, y: 42), control1: CGPoint(x: 7, y: 39), control2: CGPoint(x: 29, y: 9))
                line(CGPoint(x: 63, y: 42), CGPoint(x: 74, y: 58), CGPoint(x: 64, y: 62),
                     CGPoint(x: 62, y: 77), CGPoint(x: 49, y: 80), CGPoint(x: 49, y: 94))
                path.addQuadCurve(to: CGPoint(x: 72, y: 136), control: CGPoint(x: 70, y: 104))
                line(CGPoint(x: 33, y: 136), CGPoint(x: 39, y: 80))
            case .closeUp:
                oval(16, 58, 68, 22)
                path.move(to: CGPoint(x: 16, y: 69))
                path.addQuadCurve(to: CGPoint(x: 50, y: 111), control: CGPoint(x: 24, y: 111))
                path.addQuadCurve(to: CGPoint(x: 84, y: 69), control: CGPoint(x: 76, y: 111))
                line(CGPoint(x: 56, y: 68), CGPoint(x: 76, y: 29), CGPoint(x: 91, y: 24))
                line(CGPoint(x: 7, y: 83), CGPoint(x: 25, y: 95))
            }
        }
    }
}
