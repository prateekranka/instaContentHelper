import SwiftUI

struct MiraScriptView: View {
    var store: MiraStore
    var projectID: UUID
    var onGenerate: MiraGenerateAction
    var onAsk: () -> Void
    var body: some View {
        if let project = store.project(projectID) {
            VStack(alignment: .leading, spacing: 24) {
                MiraSectionTitle(text: "Words you can comfortably say")
                if let script = project.script {
                    Text("\(script.language) · About \(script.durationSeconds) seconds").font(
                        .callout
                    ).foregroundStyle(.secondary)
                    MiraField(title: "Hook · spoken opening", text: field(\.hook))
                    MiraField(title: "Spoken script", text: field(\.spoken))
                    MiraField(title: "Caption", text: field(\.caption))
                    Picker("Script language", selection: field(\.language)) {
                        ForEach(MiraLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Text(
                        "Changing the language label keeps your words. Ask Mira to rewrite them in another language."
                    )
                    .font(.footnote)
                    Text("Spoken words stay separate from filming instructions.")
                        .font(.footnote)
                    Stepper(
                        "About \(script.durationSeconds) seconds",
                        value: field(\.durationSeconds), in: 5...90)
                    HStack {
                        Button("Shorter") {
                            onGenerate(
                                projectID, .reviseScript, "Make it shorter while keeping my meaning", nil, nil
                            )
                        }
                        Spacer()
                        Button("More conversational") {
                            onGenerate(
                                projectID, .reviseScript,
                                "Less motivational, more conversational and everyday", nil, nil)
                        }
                    }
                    Button("Change language or ask Mira", action: onAsk)
                    Button(project.storyboard == nil ? "Make shot list" : "Update shot list") {
                        store.approveScript(projectID)
                        onGenerate(projectID, .storyboard, "Use my current reviewed script", nil, nil)
                    }.buttonStyle(MiraPrimaryStyle()).disabled(
                        script.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || store.requestState(project.job).pending)
                    Text("Make shot list confirms this script revision as its source.").font(.footnote)
                    DisclosureGroup("Script history (\(project.scripts.count) revisions)") {
                        ForEach(project.scripts.reversed()) { version in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(version.hook).font(.headline)
                                Text(version.spoken)
                                if version.id != project.activeScriptID {
                                    Button("Restore this revision") {
                                        store.restoreScript(projectID, revisionID: version.id)
                                    }
                                }
                            }.padding(.vertical, 12)
                        }
                    }
                } else {
                    Button("Draft hook, script and caption") { onGenerate(projectID, .script, "", nil, nil) }
                        .buttonStyle(MiraPrimaryStyle()).disabled(store.requestState(project.job).pending)
                    Button("Write it myself") {
                        store.writeScriptManually(projectID)
                    }
                }
            }
        }
    }
    private func field<T>(_ path: WritableKeyPath<MiraScript, T>) -> Binding<T> where T: Equatable {
        let initial = store.project(projectID)!.script![keyPath: path]
        return Binding(
            get: { store.project(projectID)?.script?[keyPath: path] ?? initial },
            set: { store.editScript(projectID, field: path, value: $0) })
    }
}

struct MiraWordsView: View {
    var store: MiraStore
    var projectID: UUID
    var onEvent: (MiraWordsEvent) -> Void
    private let simplerRequest =
        "Make the words simpler and shorter. Use everyday words. Keep my meaning and my language."

    var body: some View {
        Group {
            if let project = store.project(projectID), let script = project.script {
                page(project, script, state: store.wordsState(project))
            }
        }
        .navigationTitle("Your words").navigationBarTitleDisplayMode(.inline)
        .onAppear { onEvent(.appeared) }
    }

    private func page(_ project: MiraProject, _ script: MiraScript, state: MiraWordsState) -> some View {
        let busy = store.requestState(project.job).pending || isProposal(state)
        return MiraPage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your opening line").font(.headline)
                Text(script.hook).font(.title.bold())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("What you say").font(.headline)
                Text(script.spoken).font(.title3)
            }
            Text("About \(script.durationSeconds) seconds").font(.body).monospacedDigit()
                .foregroundStyle(.secondary)
            requestContent(state)
            if !project.isApproved {
                Button("Sounds like me") { onEvent(.approve) }.buttonStyle(MiraPrimaryStyle())
                    .disabled(busy).accessibilityIdentifier("mira.words.approve")
            } else if project.storyboard == nil || !project.storyboardIsStale {
                Button(MiraNextAction.startFilming.title) { onEvent(.startFilming) }.buttonStyle(MiraPrimaryStyle())
                    .disabled(busy || isOpening(state)).accessibilityIdentifier("mira.words.start")
            }
            Button("Make it simpler") { onEvent(.send(simplerRequest)) }.buttonStyle(.bordered)
                .controlSize(.large).disabled(busy).accessibilityIdentifier("mira.words.simpler")
            if case .changing(let note) = state {
                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                MiraTextInput(
                    title: "What should change?", text: Binding(get: { note }, set: { onEvent(.note($0)) }),
                    axis: .vertical
                ).lineLimit(2...4).font(.title3).accessibilityIdentifier("mira.words.note")
                Button(state.nextAction?.title ?? "Send") { onEvent(.send(text)) }
                    .buttonStyle(.bordered).controlSize(.large).disabled(busy || text.isEmpty)
                    .accessibilityIdentifier("mira.words.send")
                Button("Cancel") { onEvent(.cancelChange) }.buttonStyle(.bordered).controlSize(.large)
            } else {
                Button("Change it") { onEvent(.change) }.buttonStyle(.bordered).controlSize(.large)
                    .disabled(busy).accessibilityIdentifier("mira.words.change")
            }
        }
    }

    @ViewBuilder private func requestContent(_ state: MiraWordsState) -> some View {
        switch state {
        case .waiting:
            Text("Waiting to start…").font(.title3.weight(.semibold))
                .accessibilityIdentifier("mira.words.waiting")
            Text("Mira starts this when your other ideas are done.").font(.body)
            stopButton("mira.words.waiting.stop")
        case .writing(let operation):
            HStack(spacing: 12) {
                ProgressView()
                Text(operation == .reviseStoryboard ? "Updating your shots…" : "Mira is writing a new version…")
                    .font(.title3)
                    .accessibilityIdentifier("mira.words.working")
            }
            stopButton("mira.words.stop")
        case .reconnecting:
            Text("Mira has not heard back yet.").font(.body)
            Button("Check again") { onEvent(.reconnect) }.buttonStyle(.bordered).controlSize(.large)
            stopButton("mira.words.stop")
        case .stopping:
            ProgressView("Stopping…")
        case .proposal(let proposal):
            MiraSectionTitle(text: "Mira's new version")
            Text(proposal.hook).font(.title.bold())
            Text(proposal.spoken).font(.title3)
            Text("About \(proposal.durationSeconds) seconds").font(.body).monospacedDigit()
                .foregroundStyle(.secondary)
            Button(MiraNextAction.reviewProposal.title) { onEvent(.useProposal) }.buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.words.use")
            keepButton("mira.words.keep")
        case .needsShots:
            Text("Mira could not update your shots. Try again?").font(.title3)
            Button(MiraNextAction.retryShots.title) { onEvent(.retry) }.buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.words.shots.retry")
        case .retry:
            Text("Mira could not finish. Try again?").font(.title3)
            Button(MiraNextAction.retry.title) { onEvent(.retry) }.buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.words.retry")
            keepButton("mira.words.failed.keep")
        case .reviewing, .ready, .changing, .opening, .applyingShots, .shotUpdateFailed:
            EmptyView()
        }
    }

    private func isOpening(_ state: MiraWordsState) -> Bool {
        if case .opening = state { return true }
        return false
    }

    private func isProposal(_ state: MiraWordsState) -> Bool {
        if case .proposal = state { return true }
        return false
    }

    private func stopButton(_ id: String) -> some View {
        Button(MiraNextAction.stop.title) { onEvent(.stop) }.buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier(id)
    }

    private func keepButton(_ id: String) -> some View {
        Button("Keep mine") { onEvent(.keepWords) }.buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier(id)
    }
}
