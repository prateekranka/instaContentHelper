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
                            || project.job?.state == .working)
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
                        .buttonStyle(MiraPrimaryStyle()).disabled(project.job?.state == .working)
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
    var onGenerate: MiraGenerateAction
    var onReconnect: (UUID) -> Void
    var onCancel: (UUID) -> Void
    var onApproved: () -> Void
    @State private var changing = false
    @State private var note = ""
    @State private var opened = false
    @State private var stuck = false
    private let simplerRequest =
        "Make the words simpler and shorter. Use everyday words. Keep my meaning and my language."
    private let shotsRequest =
        "Update the words to say and the on-screen text in each shot to match my approved words. Keep the same shots, places and framing."

    var body: some View {
        Group {
            if let project = store.project(projectID), let script = project.script {
                page(project, script)
            }
        }
        .navigationTitle("Your words").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            opened = false
            if let job = store.project(projectID)?.job, job.state == .working,
                !store.hasActiveRequest(projectID)
            {
                onReconnect(projectID)
            }
            advance()
        }
        .onChange(of: store.project(projectID)?.job) { _, _ in advance() }
    }

    private func page(_ project: MiraProject, _ script: MiraScript) -> some View {
        let job = project.job
        let working = job?.state == .working
        let approved = project.approvedScriptID == script.id
        let needsShots = project.storyboard != nil && project.storyboardIsStale
        let proposal = proposedScript(job)
        let busy = working || proposal != nil
        let applying = job?.input.operation == .reviseStoryboard && job?.state == .succeeded && !stuck
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
            if working, let job, store.isWaitingToStart(job.id) {
                Text("Waiting to start…").font(.title3.weight(.semibold))
                    .accessibilityIdentifier("mira.words.waiting")
                Text("Mira starts this when your other ideas are done.").font(.body)
                Button("Stop") { onCancel(projectID) }.buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("mira.words.waiting.stop")
            } else if working {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(job?.input.operation == .reviseStoryboard ? "Updating your shots…" : "Mira is writing a new version…")
                        .font(.title3)
                }
                if !store.hasActiveRequest(projectID) {
                    Text("Mira has not heard back yet.").font(.body)
                    Button("Check again") { onReconnect(projectID) }.buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button("Stop") { onCancel(projectID) }.buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("mira.words.stop")
            } else if let proposal {
                MiraSectionTitle(text: "Mira's new version")
                Text(proposal.hook).font(.title.bold())
                Text(proposal.spoken).font(.title3)
                Text("About \(proposal.durationSeconds) seconds").font(.body).monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Use this") {
                    store.applyProposal(projectID)
                    store.visit(projectID, screen: .words)
                }.buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.words.use")
                Button("Keep mine") { clearJob() }.buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("mira.words.keep")
            } else if approved && needsShots && !applying {
                Text("Mira could not update your shots. Try again?").font(.title3)
                Button("Try again") { requestShots() }.buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.words.shots.retry")
            } else if let job, failed(job) {
                Text("Mira could not finish. Try again?").font(.title3)
                Button("Try again") {
                    onGenerate(
                        projectID, job.input.operation, job.input.request, job.input.targetShotID,
                        job.input.profile.language)
                }.buttonStyle(MiraPrimaryStyle()).accessibilityIdentifier("mira.words.retry")
                Button("Keep mine") { clearJob() }.buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("mira.words.failed.keep")
            }
            if !(approved && needsShots) {
                if approved {
                    Button("Start filming") { open() }.buttonStyle(MiraPrimaryStyle())
                        .disabled(busy || opened).accessibilityIdentifier("mira.words.start")
                } else {
                    Button("Sounds like me") { approve() }.buttonStyle(MiraPrimaryStyle())
                        .disabled(busy).accessibilityIdentifier("mira.words.approve")
                }
            }
            Button("Make it simpler") { send(simplerRequest) }.buttonStyle(.bordered)
                .controlSize(.large).disabled(busy).accessibilityIdentifier("mira.words.simpler")
            if changing {
                MiraTextInput(title: "What should change?", text: $note, axis: .vertical).lineLimit(2...4)
                    .font(.title3)
                    .accessibilityIdentifier("mira.words.note")
                Button("Send") { send(note.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mira.words.send")
                Button("Cancel") {
                    changing = false
                    note = ""
                }.buttonStyle(.bordered).controlSize(.large)
            } else {
                Button("Change it") { changing = true }.buttonStyle(.bordered).controlSize(.large)
                    .disabled(busy).accessibilityIdentifier("mira.words.change")
            }
        }
    }

    private func proposedScript(_ job: MiraJob?) -> MiraScript? {
        guard let job, job.input.operation == .reviseScript, job.state == .succeeded else { return nil }
        return job.output?.script
    }

    private func failed(_ job: MiraJob) -> Bool {
        guard job.input.operation == .reviseScript || job.input.operation == .reviseStoryboard else {
            return false
        }
        return job.state == .failed || job.state == .cancelled
    }

    private func clearJob() { store.update(projectID) { $0.job = nil } }

    private func requestShots() {
        stuck = false
        onGenerate(projectID, .reviseStoryboard, shotsRequest, nil, nil)
    }

    private func send(_ text: String) {
        guard !text.isEmpty else { return }
        onGenerate(projectID, .reviseScript, text, nil, nil)
        if store.project(projectID)?.job?.state == .working {
            changing = false
            note = ""
        }
    }

    private func approve() {
        guard let project = store.project(projectID), let script = project.script,
            project.approvedScriptID != script.id, project.job?.state != .working
        else { return }
        store.approveWords(projectID)
        guard let updated = store.project(projectID) else { return }
        if updated.storyboard != nil && updated.storyboardIsStale {
            requestShots()
        } else {
            open()
        }
    }

    private func open() {
        guard !opened else { return }
        opened = true
        onApproved()
    }

    private func advance() {
        guard !opened, let project = store.project(projectID), let script = project.script,
            project.approvedScriptID == script.id, let job = project.job,
            job.input.operation == .reviseStoryboard, job.state == .succeeded,
            job.output?.storyboard != nil
        else { return }
        store.applyProposal(projectID)
        store.visit(projectID, screen: .words)
        if let updated = store.project(projectID), updated.job == nil, !updated.storyboardIsStale {
            open()
        } else {
            stuck = true
        }
    }
}
