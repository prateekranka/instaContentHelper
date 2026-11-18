import SwiftUI

struct MiraStoryboardView: View {
    var store: MiraStore
    var projectID: UUID
    var onUpdate: () -> Void
    var body: some View {
        if let project = store.project(projectID), let board = project.storyboard {
            VStack(alignment: .leading, spacing: 20) {
                MiraSectionTitle(text: "Your filming plan")
                Text(
                    "About \(board.shots.reduce(0){$0+$1.editedSeconds}) seconds edited · \(board.shots.count) shots"
                ).font(.headline)
                if project.storyboardIsStale {
                    Text(
                        "This shot list is out of date. Your earlier plan and filming history are preserved."
                    ).font(.headline)
                    Button("Update shot list", action: onUpdate).buttonStyle(MiraPrimaryStyle())
                        .disabled(project.job?.state == .working)
                } else {
                    NavigationLink(value: MiraRoute.shooting(projectID)) {
                        Text(project.startedFilming ? "Continue filming" : "Start filming").frame(
                            maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(MiraPrimaryStyle())
                }
                ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Shot \(index + 1)").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        MiraShotPicture(shot: shot, number: index + 1)
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
                        DisclosureGroup("More filming details") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Where: \(shot.location)")
                                if !shot.props.isEmpty { Text("What you need: \(shot.props)") }
                                Text("Record for about \(shot.recordingSeconds) seconds.")
                                Text(shot.action)
                                if !shot.simplerAlternative.isEmpty {
                                    Text("Simpler option: \(shot.simplerAlternative)")
                                }
                            }.font(.title3).padding(.top, 12)
                        }
                        .font(.headline)
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
                } else if project.brief.confirmed {
                    Text("Brand requirements confirmed").font(.headline)
                }
            }
        }
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
    var onAsk: (UUID) -> Void
    var body: some View {
        MiraPage {
            if let project = store.project(projectID), let board = project.storyboard,
                !board.shots.isEmpty
            {
                let index = min(max(0, project.shotIndex), board.shots.count - 1)
                let shot = board.shots[index]
                Text("Shot \(index+1) of \(board.shots.count)").font(.title2)
                Text("\(board.shots.filter{project.filmed.contains($0.id)}.count) filmed by you").font(
                    .callout)
                MiraShotPicture(shot: shot, number: index + 1)
                Text(shot.purpose).font(.system(.largeTitle, design: .serif))
                Text(
                    "Record about \(shot.recordingSeconds) seconds · Use about \(shot.editedSeconds) seconds in your edit"
                )
                MiraShotDetails(shot: shot)
                if project.storyboardIsStale {
                    Text("The script or brief changed. Update the shot list before continuing.").font(
                        .headline)
                }
                if project.needsReview.contains(shot.id) {
                    Text("This shot changed. Check these instructions before filming again.").font(.headline)
                }
                Button(
                    project.filmed.contains(shot.id)
                        ? "Mark not filmed"
                        : (project.needsReview.contains(shot.id) ? "Reviewed and filmed" : "Mark filmed")
                ) {
                    store.toggleFilmed(projectID, shotID: shot.id)
                }.buttonStyle(MiraPrimaryStyle()).disabled(project.storyboardIsStale)
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
                    Text("Your filming checklist is complete.").font(.headline)
                }
            } else {
                Text("Make a shot list before filming.")
            }
        }.navigationTitle("Filming").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                store.startFilming(projectID)
            }
    }
    private func move(_ index: Int) {
        store.moveShot(projectID, to: index)
    }
}

struct MiraShotPicture: View {
    let shot: MiraShot
    let number: Int
    var showSeconds = false
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth = 49.0

    var body: some View {
        let width = showSeconds ? min(thumbnailWidth, 68) : 88
        VStack(spacing: 5) {
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
            }.frame(width: width, height: width * 1.5)
            if showSeconds { Text("\(shot.editedSeconds)s").font(.body.monospacedDigit()) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shot \(number), \(shot.pictureType.label), \(shot.editedSeconds) seconds")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("mira.shot.picture.\(number)")
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
