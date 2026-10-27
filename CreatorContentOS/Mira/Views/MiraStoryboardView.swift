import SwiftUI

struct MiraStoryboardView: View {
    var store: MiraStore
    var projectID: UUID
    var onAsk: () -> Void
    var onUpdate: () -> Void
    var body: some View {
        if let project = store.project(projectID), let board = project.storyboard {
            VStack(alignment: .leading, spacing: 24) {
                MiraSectionTitle(text: "Your filming plan")
                Text(
                    "About \(board.shots.reduce(0){$0+$1.editedSeconds}) seconds edited · \(board.shots.count) shots"
                ).font(.headline)
                Text("Locations: \(Set(board.shots.map(\.location)).sorted().joined(separator:", "))")
                Text("Props: \(Set(board.shots.map(\.props)).sorted().joined(separator:"; "))")
                if board.shots.contains(where: { $0.voiceover }) {
                    Text("Voiceover: record the marked spoken lines separately in a quiet place.").font(
                        .callout)
                }
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
                Button("Ask Mira about this plan", action: onAsk)
                ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                    DisclosureGroup {
                        MiraShotDetails(shot: shot)
                        if project.needsReview.contains(shot.id) {
                            Text("Changed shot · review before filming").font(.headline)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index+1). \(shot.purpose)").font(.headline)
                            Text(
                                "\(shot.editedSeconds)s edited · Record about \(shot.recordingSeconds)s\(project.filmed.contains(shot.id) ? " · Filmed by you" : "")"
                            ).font(.callout)
                        }
                    }
                    Divider()
                }
                if !board.mappings.isEmpty {
                    MiraSectionTitle(text: "Brand requirements included in the plan")
                    Text("This checks the plan, not a finished video.").font(.footnote)
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
                }
            }
        }
    }
}
struct MiraShotDetails: View {
    var shot: MiraShot
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phone placement").font(.headline)
            Text(shot.placement)
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
