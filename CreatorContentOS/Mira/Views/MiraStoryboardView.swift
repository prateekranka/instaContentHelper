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
