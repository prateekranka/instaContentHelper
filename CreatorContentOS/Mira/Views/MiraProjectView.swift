import SwiftUI

struct MiraProjectView: View {
    var store: MiraStore
    let projectID: UUID
    let tab: MiraMainTab
    var onSheet: (MiraSheet) -> Void
    var onGenerate: MiraGenerateAction
    var onReconnect: (UUID) -> Void
    var onCancel: (UUID) -> Void
    var body: some View {
        Group {
            if let project = store.project(projectID) {
                let showingShots = project.selectedIdeaID != nil && store.editorScreen(project, tab: tab) == .shots
                    && project.storyboard != nil
                MiraPage {
                    MiraTaskHeading(step: store.taskStep(.editor(projectID), in: project, tab: tab))
                    if project.isDemo {
                        Text("Example — not your content").font(.caption).foregroundStyle(
                            MiraTheme.accent)
                    }
                    if project.todayCards?.isEmpty == false {
                        NavigationLink("Today's ideas", value: MiraRoute.todayCards(projectID))
                    }
                    Text(project.stage.title).font(.callout).foregroundStyle(.secondary)
                    MiraTextInput(
                        title: "Project name",
                        text: Binding(
                            get: { store.project(projectID)?.title ?? "" },
                            set: { value in
                                store.update(projectID, immediate: false) {
                                    $0.title = value
                                    $0.updatedAt = Date()
                                }
                            }),
                        boxed: false
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
                            Picker(
                                "Project section",
                                selection: Binding(
                                    get: { store.editorScreen(project, tab: tab) },
                                    set: { store.visit(projectID, screen: $0, tab: tab) }
                                )
                            ) {
                                Text("Script").tag(MiraProjectScreen.script)
                                Text("Shots").tag(MiraProjectScreen.shots)
                            }.pickerStyle(.segmented)
                        }
                        if showingShots {
                            MiraStoryboardView(
                                store: store, projectID: projectID, tab: tab,
                                onUpdate: {
                                    if project.isApproved {
                                        onGenerate(
                                            projectID, .storyboard,
                                            "Update to match my current script and confirmed requirements", nil,
                                            nil)
                                    } else {
                                        store.navigate(.showWords(projectID))
                                    }
                                })
                        } else {
                            MiraScriptView(
                                store: store, projectID: projectID, onGenerate: onGenerate,
                                onAsk: { onSheet(.ask(projectID, .reviseScript, nil)) })
                        }
                        if !showingShots {
                            Button("Choose another idea") { store.chooseAnotherIdea(projectID) }
                        }
                    }
                    if !showingShots {
                        Divider()
                        if case .confirmed = project.briefState {
                            Text("Brand requirements confirmed · Included in the plan when mapped below").font(
                                .footnote)
                        }
                        projectActions(project)
                    }
                }
                .navigationTitle("Your Reel")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showingShots {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                projectActions(project)
                                Button("Choose another idea") { store.chooseAnotherIdea(projectID) }
                            } label: {
                                Label("Plan options", systemImage: "ellipsis.circle")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Project unavailable", systemImage: "book.closed",
                    description: Text("It may have been deleted."))
            }
        }
    }
    @ViewBuilder private func projectActions(_ project: MiraProject) -> some View {
        Button("Add brand requirements") { onSheet(.brief(projectID)) }
        if !project.undo.isEmpty {
            Button("Undo last content change") { store.update(projectID) { $0.undoLastChange() } }
        }
        ShareLink(item: shareText(project)) {
            Label("Share current plan", systemImage: "square.and.arrow.up")
        }
    }
    private func ideas(_ project: MiraProject) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            MiraSectionTitle(text: "What do you have time for?")
            MiraVoiceTextField(
                title: "Tell Mira", text: binding(\.request), language: store.document.profile.language)
            Text(
                "You can change these. This is time to get ready and film. Set the Reel length below."
            ).font(.footnote)
            Stepper(
                "Prepare and film: \(project.constraints.filmingMinutes) minutes",
                value: constraint(\.filmingMinutes), in: 1...180)
            HStack {
                ForEach([10, 20, 45], id: \.self) { minutes in
                    Button("\(minutes) min") {
                        store.setConstraint(\.filmingMinutes, to: minutes, in: projectID)
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
            }.buttonStyle(MiraPrimaryStyle()).disabled(store.requestState(project.job).pending)
            Button("Adjust with Ask Mira") { onSheet(.ask(projectID, .ideas, nil)) }
            Button("Add my own idea") { onSheet(.manualIdea(projectID)) }
            let displayedIdeas =
                Array(project.ideas.suffix(3)) + Array(project.ideas.dropLast(min(3, project.ideas.count)))
            ForEach(Array(displayedIdeas.enumerated()), id: \.element.id) { index, idea in
                VStack(alignment: .leading, spacing: 12) {
                    if index == 0 {
                        Text("A simple place to start").font(.caption).foregroundStyle(MiraTheme.accent)
                    }
                    Text(idea.title).font(.title2.weight(.semibold))
                    Text(idea.hook).font(.headline)
                    Text(idea.visual)
                    Text(idea.fit).foregroundStyle(.secondary)
                    Text("About \(idea.filmingMinutes) minutes to film · \(idea.setup)").font(.callout)
                    Button("Use this idea") { store.chooseIdea(projectID, ideaID: idea.id) }.buttonStyle(
                        MiraPrimaryStyle())
                    Button("Adjust this idea") { onSheet(.adjustIdea(projectID, idea.id)) }
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
                store.setConstraint(path, to: value, in: projectID)
            })
    }
    private func shareText(_ p: MiraProject) -> String {
        var text = "\(p.title)\n\(p.stage.title)\n"
        if let s = p.script {
            text += "\nHook: \(s.hook)\n\nSpoken: \(s.spoken)\n\nCaption: \(s.caption)\n"
        }
        if let b = p.storyboard {
            for (i, shot) in b.shots.enumerated() {
                text +=
                    "\nShot \(i+1) · \(shot.editedSeconds)s edited\n\(shot.placement)\n"
                if !shot.distance.isEmpty { text += "Distance: \(shot.distance)\n" }
                if !shot.framing.isEmpty { text += "Framing: \(shot.framing)\n" }
                text += "\(shot.action)\n\(shot.words)\n"
                if !shot.onScreenText.isEmpty { text += "On-screen text: \(shot.onScreenText)\n" }
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
            let state = store.requestState(job)
            switch state {
            case .waitingToStart:
                Text("Waiting to start…").font(.headline)
            case .waitingToRetry:
                ProgressView(MiraAIRequest.retryMessage)
            case .sending, .working:
                ProgressView("Mira is working")
            case .stopping:
                ProgressView("Stopping…")
            case .needsReconnect(let reason):
                if let reason { Text(reason).font(.callout) }
                Button("Check again") { onReconnect(project.id) }
            case .failed(let reason):
                if let reason { Text(reason).font(.callout) }
                Text("Mira could not finish. Try again?")
                Button("Try a new request", action: onRegenerate)
            case .stopped:
                Text("Stopped. Try again?")
                Button("Try a new request", action: onRegenerate)
            case .idle, .done: EmptyView()
            }
            if state.pending, state != .stopping {
                Text("Your work is saved. You can leave and reconnect this request later.").font(.callout)
                Button("Cancel generation", role: .cancel) { onCancel(project.id) }
            }
            if let output = job.output {
                MiraSectionTitle(text: "Mira's new version")
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
                        if !shot.distance.isEmpty { Text("Distance: \(shot.distance)") }
                        if !shot.framing.isEmpty { Text("Framing: \(shot.framing)") }
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
                    Button("Use this") { store.applyProposal(project.id) }.buttonStyle(
                        MiraPrimaryStyle()
                    ).disabled(!output.conflicts.isEmpty)
                }
                Button("Keep mine") { store.update(project.id) { $0.job = nil } }
                if job.input.operation == .reviseScript, !job.input.request.isEmpty {
                    Button("Remember this tone preference for future scripts") {
                        store.remember(job.input.request)
                    }
                }
            }
        }.padding(16).overlay(RoundedRectangle(cornerRadius: 8).stroke(MiraTheme.accent, lineWidth: 1))
    }
}
