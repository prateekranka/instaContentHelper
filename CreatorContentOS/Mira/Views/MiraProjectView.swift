import SwiftUI

struct MiraProjectView: View {
    var store: MiraStore
    let projectID: UUID
    var onSheet: (MiraSheet) -> Void
    var onGenerate: MiraGenerateAction
    var onReconnect: (UUID) -> Void
    var onCancel: (UUID) -> Void
    @State private var section = "Script"
    var body: some View {
        Group {
            if let project = store.project(projectID) {
                MiraPage {
                    if project.isDemo {
                        Text("DEMO · Example generation, no AI request").font(.caption).foregroundStyle(
                            MiraTheme.olive)
                    }
                    Text(project.stage.rawValue).font(.callout).foregroundStyle(.secondary)
                    TextField(
                        "Project name",
                        text: Binding(
                            get: { store.project(projectID)?.title ?? "" },
                            set: { value in
                                store.update(projectID, immediate: false) {
                                    $0.title = value
                                    $0.updatedAt = Date()
                                }
                            })
                    ).font(.system(.title, design: .serif)).accessibilityLabel("Project name")
                    if let job = project.job {
                        MiraJobView(
                            store: store, project: project, job: job, onReconnect: onReconnect,
                            onCancel: onCancel,
                            onRegenerate: {
                                onGenerate(
                                    projectID, job.input.operation, job.input.request, job.input.targetShotID,
                                    job.input.profile.language)
                            })
                    }
                    if project.selectedIdeaID == nil {
                        ideas(project)
                    } else {
                        if let idea = project.idea {
                            Text(idea.title).font(.headline)
                            Text(idea.visual)
                        }
                        if project.storyboard != nil {
                            Picker("Project section", selection: $section) {
                                Text("Script").tag("Script")
                                Text("Shots").tag("Shots")
                            }.pickerStyle(.segmented)
                        }
                        if section == "Shots", project.storyboard != nil {
                            MiraStoryboardView(
                                store: store, projectID: projectID,
                                onAsk: { onSheet(.ask(projectID, .reviseStoryboard, nil)) },
                                onUpdate: {
                                    onGenerate(
                                        projectID, .storyboard,
                                        "Update to match my current script and confirmed requirements", nil,
                                        nil)
                                })
                        } else {
                            MiraScriptView(
                                store: store, projectID: projectID, onGenerate: onGenerate,
                                onAsk: { onSheet(.ask(projectID, .reviseScript, nil)) })
                        }
                        Button("Choose another idea") {
                            store.update(projectID) {
                                $0.selectedIdeaID = nil
                                $0.touch()
                            }
                        }
                    }
                    Divider()
                    Button("Add brand requirements") { onSheet(.brief(projectID)) }
                    if project.brief.confirmed {
                        Text("Brand requirements confirmed · Included in the plan when mapped below").font(
                            .footnote)
                    }
                    if !project.undo.isEmpty {
                        Button("Undo last content change") { store.update(projectID) { $0.undoLastChange() } }
                    }
                    ShareLink(item: shareText(project)) {
                        Label("Share current plan", systemImage: "square.and.arrow.up")
                    }
                }.navigationTitle("Your Reel").navigationBarTitleDisplayMode(.inline)
                    .onAppear {
                        section = project.storyboard == nil ? "Script" : "Shots"
                        store.document.position = MiraPosition(projectID: projectID)
                        store.save()
                    }
            } else {
                ContentUnavailableView(
                    "Project unavailable", systemImage: "book.closed",
                    description: Text("It may have been deleted."))
            }
        }
    }
    private func ideas(_ project: MiraProject) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            MiraSectionTitle(text: "What do you have time for?")
            MiraVoiceTextField(
                title: "Tell Mira", text: binding(\.request), language: store.document.profile.language)
            Button("Read constraints from my request") {
                store.update(projectID) {
                    $0.constraints.populate(from: $0.request)
                    $0.touch()
                }
            }
            Text(
                "These are editable assumptions. Preparation and filming time is separate from the final Reel length."
            ).font(.footnote)
            Stepper(
                "Prepare and film: \(project.constraints.filmingMinutes) minutes",
                value: constraint(\.filmingMinutes), in: 1...180)
            HStack {
                ForEach([10, 20, 45], id: \.self) { minutes in
                    Button("\(minutes) min") {
                        store.update(projectID) {
                            $0.constraints.filmingMinutes = minutes
                            $0.touch()
                        }
                    }
                }
            }
            MiraField(title: "Filming location", text: constraint(\.location))
            Picker("Reel style", selection: constraint(\.style)) {
                ForEach(MiraStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Stepper(
                "Final Reel: about \(project.constraints.reelSeconds) seconds",
                value: constraint(\.reelSeconds), in: 10...90, step: 5)
            MiraField(title: "Available equipment", text: constraint(\.equipment))
            Button(project.ideas.isEmpty ? "Show three ideas" : "More ideas") {
                onGenerate(projectID, .ideas, project.request, nil, nil)
            }.buttonStyle(MiraPrimaryStyle()).disabled(project.job?.state == .working)
            Button("Adjust with Ask Mira") { onSheet(.ask(projectID, .ideas, nil)) }
            Button("Add my own idea") { onSheet(.manualIdea(projectID)) }
            ForEach(Array(project.ideas.enumerated()), id: \.element.id) { index, idea in
                VStack(alignment: .leading, spacing: 12) {
                    if index == max(0, project.ideas.count - 3) {
                        Text("A simple place to start").font(.caption).foregroundStyle(MiraTheme.olive)
                    }
                    Text(idea.title).font(.title2.weight(.semibold))
                    Text(idea.hook).font(.headline)
                    Text(idea.visual)
                    Text(idea.fit).foregroundStyle(.secondary)
                    Text("About \(idea.filmingMinutes) minutes to film · \(idea.setup)").font(.callout)
                    Button("Use this idea") { store.update(projectID) { $0.select(idea) } }.buttonStyle(
                        MiraPrimaryStyle())
                }
                Divider()
            }
        }
    }
    private func binding(_ path: WritableKeyPath<MiraProject, String>) -> Binding<String> {
        Binding(
            get: { store.project(projectID)?[keyPath: path] ?? "" },
            set: { value in
                store.update(projectID, immediate: false) {
                    $0[keyPath: path] = value
                    $0.touch()
                }
            })
    }
    private func constraint<T>(_ path: WritableKeyPath<MiraConstraints, T>) -> Binding<T> {
        let initial = store.project(projectID)!.constraints[keyPath: path]
        return Binding(
            get: { store.project(projectID)?.constraints[keyPath: path] ?? initial },
            set: { value in
                store.update(projectID) {
                    $0.constraints[keyPath: path] = value
                    $0.touch()
                }
            })
    }
    private func shareText(_ p: MiraProject) -> String {
        var text = "\(p.title)\n\(p.stage.rawValue)\n"
        if let s = p.script { text += "\nHook: \(s.hook)\n\nSpoken: \(s.spoken)\n\nCaption: \(s.caption)\n" }
        if let b = p.storyboard {
            for (i, shot) in b.shots.enumerated() {
                text +=
                    "\nShot \(i+1) · \(shot.editedSeconds)s edited\n\(shot.placement)\n\(shot.action)\n\(shot.words)\n"
            }
        }
        return text
    }
}

struct MiraJobView: View {
    var store: MiraStore
    var project: MiraProject
    var job: MiraJob
    var onReconnect: (UUID) -> Void
    var onCancel: (UUID) -> Void
    var onRegenerate: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if job.state == .working {
                ProgressView("Mira is working")
                Text("Your work is saved. You can leave and reconnect this request later.").font(.callout)
                if !store.hasActiveRequest(project.id) {
                    Button("Reconnect saved request") { onReconnect(project.id) }
                }
                Button("Cancel generation", role: .cancel) { onCancel(project.id) }
            }
            if let error = job.error { Text(error).font(.callout) }
            if job.state == .failed || job.state == .cancelled {
                Text(job.state == .cancelled ? "Generation cancelled" : "Generation failed")
                Button("Try a new request", action: onRegenerate)
            }
            if let output = job.output {
                MiraSectionTitle(text: "Review Mira’s proposal")
                if let script = output.script {
                    Text(script.hook).font(.headline)
                    Text(script.spoken)
                    Text("Caption: \(script.caption)")
                }
                if let ideas = output.ideas {
                    ForEach(ideas) {
                        Text($0.title).font(.headline)
                        Text($0.visual)
                    }
                }
                if let board = output.storyboard {
                    ForEach(Array(board.shots.enumerated()), id: \.element.id) { i, shot in
                        Text("\(i+1). \(shot.purpose)").font(.headline)
                        Text(shot.action)
                        Text(shot.placement)
                    }
                }
                if let brief = output.brief {
                    ForEach(brief.requirements) {
                        Text("\($0.kind): \($0.value)")
                        Text("Source: \($0.excerpt)").font(.callout)
                    }
                    ForEach(brief.unresolved, id: \.self) { Text("Unresolved: \($0)") }
                }
                ForEach(output.conflicts, id: \.self) { Text("Needs a choice: \($0)").font(.callout) }
                if project.inputRevision != job.inputRevision {
                    Text(
                        "Your input changed. This proposal is preserved; make a new request to use current work."
                    ).font(.callout)
                    Button("Generate from current work", action: onRegenerate)
                } else {
                    Button("Apply proposal") { store.applyProposal(project.id) }.buttonStyle(
                        MiraPrimaryStyle()
                    ).disabled(!output.conflicts.isEmpty)
                }
                Button("Discard proposal") { store.update(project.id) { $0.job = nil } }
                if job.input.operation == .reviseScript, !job.input.request.isEmpty {
                    Button("Remember this tone preference for future scripts") {
                        store.remember(job.input.request)
                    }
                }
            }
        }.padding(16).overlay(RoundedRectangle(cornerRadius: 8).stroke(MiraTheme.olive, lineWidth: 1))
    }
}
