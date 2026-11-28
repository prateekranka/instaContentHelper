import AVFoundation
import SwiftUI
import UIKit

struct MiraVoiceTextField: View {
    var title: String
    @Binding var text: String
    var language: MiraLanguage
    @Environment(MiraDependencies.self) private var dependencies
    @State private var speech: (any MiraSpeechInputService)?
    @State private var locale = "hi-IN"
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MiraField(title: title, text: $text)
            if let speech {
                Picker("Language you speak", selection: $locale) {
                    Text("Hindi").tag("hi-IN")
                    Text("English").tag("en-IN")
                }.disabled(speech.state.isRecording)
                MiraVoiceButton(speech: speech, locale: locale)
                if let message = speech.state.message {
                    Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently)
                }
                if !speech.transcript.isEmpty {
                    MiraField(
                        title: "Check your words",
                        text: Binding(
                            get: { speech.transcript }, set: { speech.transcript = $0 }
                        )
                    ).disabled(speech.state.isRecording)
                    Button("Use these words") {
                        text = speech.transcript
                        speech.transcript = ""
                    }.disabled(speech.state.isRecording)
                }
            }
            Text(
                "Your voice stays on this phone. Check the words before you send them."
            ).font(.footnote).foregroundStyle(.secondary)
        }.onAppear {
            if speech == nil { speech = dependencies.makeSpeechInput() }
            locale = language == .english ? "en-IN" : "hi-IN"
        }
        .onDisappear { speech?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                speech?.refreshPermissions()
            } else if phase == .background || speech?.state.isRecording == true {
                speech?.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
            _ in speech?.stop()
        }
    }
}
struct MiraVoiceButton: View {
    let speech: any MiraSpeechInputService
    let locale: String
    var compact = false
    var diameter: CGFloat = 60
    var onStart: () -> Void = {}

    var body: some View {
        let action = speech.state.nextAction
        let icon = speech.state.isRecording ? "stop.fill" : action == .openSettings ? "gearshape" : "mic.fill"
        Button {
            switch action {
            case .stopRecording: speech.stop()
            case .useMicrophone:
                onStart()
                Task { await speech.start(locale: locale) }
            case .openSettings:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            default: break
            }
        } label: {
            if compact {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .frame(width: diameter, height: diameter)
                    .foregroundStyle(MiraTheme.paper)
                    .background(MiraTheme.accent, in: Circle())
            } else {
                Label(action.title, systemImage: icon)
            }
        }
        .disabled(action == .wait)
        .accessibilityLabel(compact && action == .useMicrophone ? "Speak instead of typing" : action.title)
    }
}
struct MiraAskView: View {
    var store: MiraStore
    var projectID: UUID
    var operation: MiraOperation
    var target: UUID?
    var onGenerate: MiraGenerateAction
    var contextIdea: MiraIdea?
    var initialRequest = ""
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var language: MiraLanguage = .english
    @State private var explanation = false
    var body: some View {
        MiraPage {
            Text(context).font(.headline)
            if operation == .todayIdea {
                if let contextIdea { Text(contextIdea.title).font(.title2) }
            } else {
                Text("Mira proposes a change here. You review and Apply before it replaces your work.")
            }
            if operation == .reviseScript {
                Button("Shorter") { request = "Make this shorter while preserving the main point" }
                Button("More conversational") {
                    request = "Less motivational. Make it sound more like my everyday speech."
                }
                Picker(
                    "Output language",
                    selection: Binding(
                        get: { language },
                        set: { value in
                            language = value
                            if request.isEmpty {
                                request =
                                    "Change the script to \(value.rawValue), keeping my meaning and tone."
                            }
                        })
                ) {
                    ForEach(MiraLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            if operation == .reviseStoryboard || operation == .reviseShot {
                MiraField(
                    title: "Filming location to use",
                    text: Binding(
                        get: { store.project(projectID)?.constraints.location ?? "Home" },
                        set: { value in
                            store.update(projectID) {
                                $0.constraints.location = value
                                $0.touch()
                            }
                        }))
            }
            MiraVoiceTextField(
                title: "What would help?", text: $request, language: store.document.profile.language)
            if explanation, let p = store.project(projectID) {
                Text(
                    "This Reel is planned for \(p.constraints.location), with \(p.constraints.filmingMinutes) minutes to prepare and film. The shot list separates recording time from edited duration. Voiceover is recorded separately where marked. Filmed status is your own checklist."
                )
            }
            if operation != .todayIdea { Button("Explain this plan") { explanation.toggle() } }
            if store.requestState(store.project(projectID)?.job).pending {
                Text(
                    "Mira is working on your earlier request. Reconnect or cancel it from this project first."
                )
                .font(.callout)
            }
        }.miraBottomAction {
            Button(operation == .ideas ? "Get ideas" : "Propose change") {
                let lower = request.lowercased()
                if ["publish to", "upload video", "send payment"].contains(where: {
                    lower.contains($0)
                }) {
                    store.reportError("Mira helps with ideas, words and filming plans. Publishing, editing media and payments are outside this notebook.")
                    return
                }
                onGenerate(
                    projectID, operation, request, target, operation == .reviseScript ? language : nil)
                dismiss()
            }.buttonStyle(MiraPrimaryStyle()).disabled(
                request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || store.requestState(store.project(projectID)?.job).pending)
        }.navigationTitle("Ask Mira").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .onAppear {
            if request.isEmpty { request = initialRequest }
            if operation != .todayIdea, let idea = contextIdea, request.isEmpty {
                request =
                    "Adjust this idea: \(idea.title). Hook: \(idea.hook). Viewers see: \(idea.visual). My change: "
            }
            language =
                store.project(projectID)?.script.flatMap { MiraLanguage(rawValue: $0.language) }
                ?? store.document.profile.language
        }
    }
    private var context: String {
        switch operation {
        case .ideas: "Ideas for this Reel"
        case .todayIdea: "Change this idea"
        case .reviseScript: "Revise this script"
        case .script: "Draft words for this Reel"
        case .reviseShot: "Make this shot easier"
        case .reviseStoryboard: "Revise this filming plan"
        default: "This project"
        }
    }
}
struct MiraProfileView: View {
    var store: MiraStore
    var onStepByStep: () -> Void
    var onDemo: () -> Void
    @AppStorage(MiraLook.defaultsKey) private var look: MiraLook = .system
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(MiraProblemReports.self) private var problemReports
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        MiraPage {
            lookSetting
            Divider()
            Text(
                "A little context helps Mira write like you. Every field is optional; you can come back later."
            )
            MiraField(title: "Your name", text: field(\.name))
            MiraField(title: "Themes you care about", text: field(\.themes))
            MiraField(title: "Your audience", text: field(\.audience))
            Picker("Preferred output language", selection: field(\.language)) {
                ForEach(MiraLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Hindi and Hinglish writing", selection: field(\.writingSystem)) {
                ForEach(MiraWritingSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            MiraField(title: "How you like to sound", text: field(\.tone))
            MiraField(title: "Things you would not say", text: field(\.avoid))
            Toggle("I usually film alone", isOn: field(\.solo))
            MiraField(title: "Optional real captions or spoken samples", text: field(\.samples))
            Text("Mira uses the context you provide here to write like you. Instagram connects only if you choose it, and only to read your insights.")
                .font(
                    .footnote)
            Divider()
            MiraSectionTitle(text: "How you're doing")
            NavigationLink {
                MiraInsightsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                        .foregroundStyle(MiraTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instagram insights").font(.headline)
                        Text("Followers, reach and saves")
                            .font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MiraTheme.ink.opacity(0.4))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(MiraTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MiraTheme.ink.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MiraTheme.ink)
            .accessibilityIdentifier("mira.profile.insights")
            Text("Mira only reads your insights — it never posts for you.")
                .font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
            Divider()
            MiraSectionTitle(text: "Other ways to start")
            Button(action: onStepByStep) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan step by step").font(.headline)
                    Text("Opens from My Brand. You choose each part yourself.").font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("mira.profile.stepByStep")
            Button(action: onDemo) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try the example notebook").font(.headline)
                    Text("Example — not your content. It uses no AI.").font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("mira.profile.demo")
            Divider()
            MiraSectionTitle(text: "Live generation")
            if case .live = appState.runtime.mode {
                Text("Account connected")
                Text(services.aiConsentStatusCopy)
                NavigationLink("Review AI data permission") { MiraConsentReviewView() }
                Button("Sign out") { Task { await appState.signOut() } }
            } else {
                NavigationLink("Connect account") { SignInView() }
                Text(
                    appState.authenticationError
                        ?? "Saved local projects and manual editing remain available without sign-in."
                ).font(.callout)
            }
            Text(
                "Mira sends text from your profile and project to its AI partners. It also sends brand notes you confirm. Your voice stays on this phone."
            ).font(.footnote)
            if !problemReports.files.isEmpty {
                Divider()
                problemReportsRow
            }
        }.miraBottomAction {
            Button("Done") {
                store.save()
                dismiss()
            }.buttonStyle(MiraPrimaryStyle())
        }.navigationTitle("Profile")
    }

    private var problemReportsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Problem reports").font(.headline)
                let count = problemReports.files.count
                Text("\(count) \(count == 1 ? "report" : "reports")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(items: problemReports.files) {
                Text("Share")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mira.profile.problemReports")
    }

    private var lookSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiraSectionTitle(text: "Look")
            ForEach(MiraLook.allCases, id: \.self) { choice in
                Button {
                    look = choice
                } label: {
                    HStack {
                        Text(choice.title)
                        Spacer()
                        if choice == look {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                    .font(.title3)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(choice == look ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mira.profile.look")
    }

    private func field<T>(_ path: WritableKeyPath<MiraProfile, T>) -> Binding<T> {
        Binding(
            get: { store.document.profile[keyPath: path] },
            set: { value in
                store.document.profile[keyPath: path] = value
                for i in store.document.projects.indices
                where store.document.projects[i].job?.state == .working {
                    store.document.projects[i].touch()
                }
                store.save(immediate: false)
            })
    }
}
struct MiraManualIdeaView: View {
    var store: MiraStore
    var projectID: UUID
    @State private var title = ""
    @State private var hook = ""
    @State private var visual = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        MiraPage {
            MiraField(title: "Idea title", text: $title)
            MiraField(title: "Opening line", text: $hook)
            MiraField(title: "What viewers see", text: $visual)
        }.miraBottomAction {
            Button("Use my idea") {
                store.update(projectID, screen: .script) { p in
                    let idea = MiraIdea(
                        title: title, hook: hook, visual: visual, fit: "Your own idea",
                        filmingMinutes: p.constraints.filmingMinutes, setup: p.constraints.location)
                    p.ideas.append(idea)
                    p.select(idea)
                }
                dismiss()
            }.buttonStyle(MiraPrimaryStyle()).disabled(
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hook.isEmpty
                    || visual.isEmpty)
        }.navigationTitle("Your own idea").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}
struct MiraBriefView: View {
    var store: MiraStore
    var projectID: UUID
    var onGenerate: MiraGenerateAction
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let project = store.project(projectID) {
            let state = project.briefState
            MiraPage {
                Text(
                    "Paste the brand's requirements. Check and confirm the list before Mira uses it."
                )
                MiraField(
                    title: "Original brand requirements",
                    text: Binding(
                        get: { store.project(projectID)?.brief.original ?? "" },
                        set: { store.editBrief(projectID, .textChanged($0)) }))
                if state.canConfirm {
                    extractButton(project)
                } else {
                    MiraInlineAction { extractButton(project) }
                }
                Text(
                    "Apply Mira’s list in the project. Then come back here to confirm it."
                ).font(.callout)
                ForEach(project.brief.requirements) { requirement in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(requirement.kind).font(.headline)
                        MiraField(
                            title: "Required detail",
                            text: Binding(
                                get: {
                                    store.project(projectID)?.brief.requirements.first {
                                        $0.id == requirement.id
                                    }?.value ?? ""
                                },
                                set: { store.editBrief(projectID, .detailChanged(requirement.id, $0)) }))
                        Text("Source: \(requirement.excerpt)").font(.callout)
                        if !state.matchesSource(requirement) {
                            Text("Source changed · update the original and extract again").font(.headline)
                        }
                        Button("Remove requirement", role: .destructive) {
                            store.editBrief(projectID, .removeRequirement(requirement.id))
                        }
                    }
                    Divider()
                }
                if !project.brief.unresolved.isEmpty {
                    MiraSectionTitle(text: "Unresolved details")
                    ForEach(project.brief.unresolved, id: \.self) { Text($0) }
                }
                if state.canConfirm {
                    MiraInlineAction { confirmButton(state) }
                } else {
                    confirmButton(state)
                }
                Text(
                    "Missing details stay visible even after confirmation. Conflicts will need a choice before a plan can be applied."
                ).font(.footnote)
                Button("Stop using this brief") {
                    if store.editBrief(projectID, .stopUsing) { dismiss() }
                }
            }.miraBottomAction(whileEditing: true) {
                if state.canConfirm {
                    confirmButton(state)
                } else {
                    extractButton(project).buttonStyle(MiraPrimaryStyle())
                }
            }.navigationTitle("Brand requirements").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
    private func extractButton(_ project: MiraProject) -> some View {
        Button(MiraNextAction.extractRequirements.title) {
            onGenerate(
                projectID, .requirements, "Extract only supplied facts and flag missing fields", nil,
                nil)
            dismiss()
        }.disabled(project.brief.original.isEmpty || store.requestState(project.job).pending)
    }

    private func confirmButton(_ state: MiraBriefState) -> some View {
        Button(confirmTitle(state)) {
            if store.editBrief(projectID, .confirm, immediate: true) { dismiss() }
        }.buttonStyle(MiraPrimaryStyle()).disabled(!state.canConfirm)
    }

    private func confirmTitle(_ state: MiraBriefState) -> String {
        switch state {
        case .confirmed: "Requirements confirmed"
        default: MiraNextAction.confirmRequirements.title
        }
    }

}

struct MiraConsentReviewView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        MiraPage {
            MiraSectionTitle(text: "AI data permission")
            Text(
                AIConsentCopy.purposeAndDestinations.replacingOccurrences(of: "ContentHelper", with: "Mira")
            )
            Text(
                "If you say no, you can still open and edit your work. Your voice stays on this phone."
            )
            Button("Allow AI partners") {
                services.acceptAIConsent()
                dismiss()
            }.buttonStyle(MiraPrimaryStyle())
            Button("Decline AI permission") {
                services.declineAIConsent()
                dismiss()
            }
        }.navigationTitle("AI permission")
    }
}
struct MiraConsentPresenter: ViewModifier {
    @Environment(AppServices.self) private var services
    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { services.isAIConsentSheetPresented },
                set: { services.setAIConsentSheetPresented($0) })
        ) {
            NavigationStack { MiraConsentReviewView() }
        }
    }
}

struct MiraAskBar: View {
    let placeholder: String
    let language: MiraLanguage
    var enabled = true
    let onSend: (String) -> Void
    @Environment(MiraDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech: (any MiraSpeechInputService)?
    @State private var text = ""
    @State private var spokenBase = ""
    @Environment(\.miraInputFocus) private var focus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = speech?.state.message {
                Text(message).font(.footnote).accessibilityAddTraits(.updatesFrequently)
            }
            HStack(spacing: 8) {
                MiraTextInput(title: placeholder, text: $text)
                    .accessibilityIdentifier("mira.ask.bar")
                if let speech {
                    MiraVoiceButton(
                        speech: speech, locale: language == .english ? "en-IN" : "hi-IN",
                        compact: true, diameter: 44
                    ) {
                        focus?.wrappedValue = nil
                        spokenBase = text
                    }.buttonStyle(.plain)
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel("Send to Mira")
                        .disabled(speech?.state.isRecording == true)
                }
            }
        }
        .disabled(!enabled)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
        .background(MiraTheme.paper)
        .overlay(alignment: .top) { Divider() }
        .onAppear { if speech == nil { speech = dependencies.makeSpeechInput() } }
        .onDisappear { speech?.stop() }
        .onChange(of: speech?.transcript ?? "") { _, transcript in
            guard !transcript.isEmpty else { return }
            text = spokenBase.isEmpty ? transcript : "\(spokenBase) \(transcript)"
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                speech?.refreshPermissions()
            } else {
                speech?.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
            _ in speech?.stop()
        }
    }

    private func send() {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !request.isEmpty, speech?.state.isRecording != true else { return }
        focus?.wrappedValue = nil
        text = ""
        onSend(request)
    }
}

struct MiraDealDraftView: View {
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MiraPage {
            MiraField(title: "Original brand requirements", text: $text)
        }.miraBottomAction {
            let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Button("Save as a Reel brief") { onSave(request) }
                .buttonStyle(MiraPrimaryStyle()).disabled(request.isEmpty)
        }
        .navigationTitle("Brand brief")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
}
