import AVFoundation
import SwiftUI

struct MiraBrandView<Library: View>: View {
    let store: MiraStore
    let onStart: () -> Void
    let onGenerate: () -> Void
    @ViewBuilder var library: Library

    var body: some View {
        switch store.brandInterview {
        case .answering(let answers):
            MiraBrandQuestion(
                answers: answers, language: store.document.profile.language, onEdit: { store.sendBrandInterview(.edit($0)) },
                onBack: { store.sendBrandInterview(.back) }, onNext: {
                    if answers.isLast { onGenerate() } else { store.sendBrandInterview(.next) }
                }, onCancel: { store.sendBrandInterview(.reset) }, next: store.brandInterview.nextAction)
            .id(answers.index)
        case .generating:
            MiraPage { ProgressView("Making your brand doc").accessibilityIdentifier("mira.brand.wait") }
        case .failed(_, _, let message):
            MiraPage {
                Text(message)
                Button(store.brandInterview.nextAction.title, action: onGenerate).buttonStyle(MiraPrimaryStyle())
                Button("Back to your answers") { store.sendBrandInterview(.back) }
                Button("Cancel interview") { store.sendBrandInterview(.reset) }.font(.subheadline)
            }
        case .idle:
            MiraPage {
                document
                switch store.brandDocumentState {
                case .reviewing: EmptyView()
                case .empty, .confirmed: library
                }
            }.miraBottomAction {
                if case .reviewing(let draft) = store.brandDocumentState {
                    Button(store.brandDocumentState.nextAction.title) { store.sendBrandDocument(.confirm) }
                        .buttonStyle(MiraPrimaryStyle())
                        .disabled(!draft.normalized().isValid)
                        .accessibilityIdentifier("mira.brand.confirm")
                }
            }
        }
    }

    @ViewBuilder private var document: some View {
        switch store.brandDocumentState {
        case .empty:
            MiraFeedCard {
                MiraSectionTitle(text: "Tell Mira about your brand")
                Text("Answer six questions. Then review and edit what Mira writes.")
                Button(store.brandDocumentState.nextAction.title, action: onStart)
                    .buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.brand.start")
            }
        case .reviewing(let draft):
            MiraSectionTitle(text: "Your brand doc")
            editor(draft)
            Button("Cancel") { store.sendBrandDocument(.read(store.document.brandDoc)) }
        case .confirmed(let saved):
            MiraSectionTitle(text: "Your brand doc")
            VStack(alignment: .leading, spacing: 12) {
                group("What you post", saved.pillars)
                group("How you sound", [saved.tone])
                group("Who watches", [saved.audience])
                group("What you do", saved.dos)
                group("What you avoid", saved.donts)
                group("Your goals", saved.goals)
            }.accessibilityIdentifier("mira.brand.saved")
            Button(store.brandDocumentState.nextAction.title) { store.sendBrandDocument(.edit) }
                .buttonStyle(.bordered)
        }
    }

    private func group(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items.indices, id: \.self) { Text(items[$0]) }
        }
    }

    @ViewBuilder private func editor(_ draft: MiraBrandDocument) -> some View {
        list("What you post", id: "pillars", path: \.pillars, draft: draft, count: 3...5)
        MiraField(title: "How you sound", text: field(\.tone, in: draft))
            .accessibilityIdentifier("mira.brand.tone")
        MiraField(title: "Who watches", text: field(\.audience, in: draft))
            .accessibilityIdentifier("mira.brand.audience")
        list("What you do", id: "dos", path: \.dos, draft: draft, count: 0...6)
        list("What you avoid", id: "donts", path: \.donts, draft: draft, count: 0...6)
        list("Your goals", id: "goals", path: \.goals, draft: draft, count: 1...3)
        if !draft.normalized().isValid {
            Text("Fill each item with one short line. Use a different topic for each item under What you post.")
                .font(.callout)
        }
    }

    private func field(_ path: WritableKeyPath<MiraBrandDocument, String>, in draft: MiraBrandDocument) -> Binding<String> {
        Binding(get: { draft[keyPath: path] }, set: { value in
            guard case .reviewing(var current) = store.brandDocumentState else { return }
            current[keyPath: path] = value
            store.sendBrandDocument(.change(current))
        })
    }

    private func list(
        _ title: String, id: String, path: WritableKeyPath<MiraBrandDocument, [String]>,
        draft: MiraBrandDocument, count: ClosedRange<Int>
    ) -> some View {
        let items = draft[keyPath: path]
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    MiraTextInput(title: "\(title) \(index + 1)", text: Binding(
                        get: { items[index] },
                        set: { value in
                            updateList(path) { if $0.indices.contains(index) { $0[index] = value } }
                        }))
                    .accessibilityIdentifier("mira.brand.\(id).\(index + 1)")
                    if items.count > count.lowerBound {
                        Button {
                            updateList(path) { if $0.indices.contains(index) { $0.remove(at: index) } }
                        } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove \(title) item \(index + 1)")
                    }
                }
            }
            if items.count < count.upperBound {
                Button("Add item") { updateList(path) { $0.append("") } }
                    .accessibilityLabel("Add item to \(title)")
            }
        }
    }

    private func updateList(
        _ path: WritableKeyPath<MiraBrandDocument, [String]>, _ change: (inout [String]) -> Void
    ) {
        guard case .reviewing(var current) = store.brandDocumentState else { return }
        change(&current[keyPath: path])
        store.sendBrandDocument(.change(current))
    }
}

private struct MiraBrandQuestion: View {
    let answers: MiraInterviewAnswers
    let language: MiraLanguage
    let onEdit: (String) -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onCancel: () -> Void
    let next: MiraNextAction
    @Environment(MiraDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech: (any MiraSpeechInputService)?
    @State private var typedBase = ""

    var body: some View {
        MiraPage {
            Text("Question \(answers.index + 1) of \(MiraInterviewAnswers.questions.count)")
                .font(.subheadline)
                .accessibilityIdentifier("mira.brand.questionNumber")
            Text(MiraInterviewAnswers.questions[answers.index])
                .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("mira.brand.question")
            HStack(alignment: .top, spacing: 12) {
                MiraTextInput(title: "Your answer", text: Binding(get: { answers.answer }, set: { onEdit($0) }), axis: .vertical)
                    .lineLimit(3...7).font(.title3).accessibilityIdentifier("mira.brand.answer")
                if let speech {
                    MiraVoiceButton(speech: speech, locale: language == .english ? "en-IN" : "hi-IN", compact: true) {
                        typedBase = answers.answer
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mira.brand.mic")
                }
            }
            .onAppear { if speech == nil { speech = dependencies.makeSpeechInput() } }
            .onDisappear { speech?.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { speech?.refreshPermissions() }
                else { speech?.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
                speech?.stop()
            }
            .onChange(of: speech?.transcript ?? "") { _, spoken in
                guard !spoken.isEmpty else { return }
                onEdit([typedBase, spoken].filter { !$0.isEmpty }.joined(separator: " "))
            }
            if let message = speech?.state.message { Text(message).accessibilityAddTraits(.updatesFrequently) }
            if answers.index > 0 {
                Button("Back") {
                    speech?.stop()
                    onBack()
                }.accessibilityIdentifier("mira.brand.back")
            }
            Button("Cancel interview", action: onCancel).font(.subheadline)
        }.miraBottomAction {
            Button(next.title) {
                speech?.stop()
                onNext()
            }
            .buttonStyle(MiraPrimaryStyle())
            .disabled(!answers.canAdvance || speech?.state.isRecording == true)
            .accessibilityIdentifier("mira.brand.next")
        }
    }
}
