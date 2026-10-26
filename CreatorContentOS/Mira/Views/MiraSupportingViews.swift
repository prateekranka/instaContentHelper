import AVFoundation
import SwiftUI
import UIKit

struct MiraVoiceTextField: View {
    var title: String
    @Binding var text: String
    var language: MiraLanguage
    @State private var speech = MiraSpeechInput()
    @State private var locale = "hi-IN"
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MiraField(title: title, text: $text)
            Picker("Speech recognition language", selection: $locale) {
                Text("Hindi recognition").tag("hi-IN")
                Text("English recognition").tag("en-IN")
            }.disabled(speech.recording)
            Button {
                if speech.recording { speech.stop() } else { Task { await speech.start(locale: locale) } }
            } label: {
                Label(
                    speech.recording ? "Stop recording · \(speech.elapsed) seconds" : "Use microphone",
                    systemImage: speech.recording ? "stop.circle.fill" : "mic")
            }.disabled(speech.requesting)
            if speech.recording {
                Text("Recording · stops at 60 seconds").font(.headline).accessibilityAddTraits(
                    .updatesFrequently)
            }
            if !speech.transcript.isEmpty {
                MiraField(title: "Review transcript", text: $speech.transcript)
                Button("Use reviewed transcript") {
                    text = speech.transcript
                    speech.transcript = ""
                }
            }
            if let error = speech.error {
                Text(error).font(.callout)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Text(
                "Audio stays in on-device recognition memory. Review the transcript before submitting. Hinglish accuracy can vary; Hindi and English recognition are separate choices."
            ).font(.footnote).foregroundStyle(.secondary)
        }.onAppear { locale = language == .english ? "en-IN" : "hi-IN" }
            .onDisappear { speech.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { speech.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
                _ in speech.stop()
            }
    }
}
struct MiraAskView: View {
    var store: MiraStore
    var projectID: UUID
    var operation: MiraOperation
    var target: UUID?
    var onGenerate: MiraGenerateAction
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var language: MiraLanguage = .english
    @State private var explanation = false
    var body: some View {
        MiraPage {
            Text(context).font(.headline)
            Text("Mira proposes a change here. You review and Apply before it replaces your work.")
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
            Button("Explain this plan") { explanation.toggle() }
            Button(operation == .ideas ? "Get ideas" : "Propose change") {
                let lower = request.lowercased()
                if ["publish to", "upload video", "instagram analytics", "send payment"].contains(where: {
                    lower.contains($0)
                }) {
                    store.error =
                        "Mira helps with ideas, words and filming plans. Publishing, editing media and analytics are outside this notebook."
                    return
                }
                onGenerate(projectID, operation, request, target, operation == .reviseScript ? language : nil)
                dismiss()
            }.buttonStyle(MiraPrimaryStyle()).disabled(
                request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.navigationTitle("Ask Mira").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .onAppear {
            language =
                store.project(projectID)?.script.flatMap { MiraLanguage(rawValue: $0.language) }
                ?? store.document.profile.language
        }
    }
    private var context: String {
        switch operation {
        case .ideas: "Ideas for this Reel"
        case .reviseScript: "Revise this script"
        case .reviseShot: "Make this shot easier"
        case .reviseStoryboard: "Revise this filming plan"
        default: "This project"
        }
    }
}
struct MiraProfileView: View {
    var store: MiraStore
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        MiraPage {
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
            Text("Mira uses only context you provide. No Instagram account is connected or analysed.").font(
                .footnote)
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
                "Live requests send profile text, the selected project content, and confirmed brief context to the existing Supabase AI service. Recordings are not uploaded."
            ).font(.footnote)
        }.navigationTitle("Profile").toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    store.save()
                    dismiss()
                }
            }
        }
    }
    private func field<T>(_ path: WritableKeyPath<MiraProfile, T>) -> Binding<T> {
        Binding(
            get: { store.document.profile[keyPath: path] },
            set: { value in
                store.document.profile[keyPath: path] = value
                for i in store.document.projects.indices
                where store.document.projects[i].job?.state == .working { store.document.projects[i].touch() }
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
            Button("Use my idea") {
                store.update(projectID) { p in
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
            MiraPage {
                Text(
                    "Paste optional brand requirements. Mira proposes a checklist; you confirm it before generation uses it."
                )
                MiraField(
                    title: "Original brand requirements",
                    text: Binding(
                        get: { store.project(projectID)?.brief.original ?? "" },
                        set: { value in edit { $0.original = value } }))
                Button("Extract proposed requirements") {
                    onGenerate(
                        projectID, .requirements, "Extract only supplied facts and flag missing fields", nil,
                        nil)
                    dismiss()
                }.disabled(project.brief.original.isEmpty || project.job?.state == .working)
                Text(
                    "Review the extraction proposal on the project and Apply it, then return here to confirm. No code, deadline, claim or approval is assumed."
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
                                set: { value in
                                    edit { brief in
                                        if let i = brief.requirements.firstIndex(where: {
                                            $0.id == requirement.id
                                        }) {
                                            brief.requirements[i].value = value
                                        }
                                    }
                                }))
                        Text("Source: \(requirement.excerpt)").font(.callout)
                        if !project.brief.original.contains(requirement.excerpt)
                            || !project.brief.original.contains(requirement.value)
                        {
                            Text("Source changed · update the original and extract again").font(.headline)
                        }
                        Button("Remove requirement", role: .destructive) {
                            edit { $0.requirements.removeAll { $0.id == requirement.id } }
                        }
                    }
                    Divider()
                }
                if !project.brief.unresolved.isEmpty {
                    MiraSectionTitle(text: "Unresolved details")
                    ForEach(project.brief.unresolved, id: \.self) { Text($0) }
                }
                Button(project.brief.confirmed ? "Requirements confirmed" : "Confirm these requirements") {
                    store.update(projectID) {
                        $0.brief.confirmed = true
                        $0.brief.revision += 1
                        $0.touch()
                    }
                    dismiss()
                }.buttonStyle(MiraPrimaryStyle()).disabled(
                    project.brief.requirements.isEmpty
                        || project.brief.requirements.contains {
                            !project.brief.original.contains($0.excerpt)
                                || !project.brief.original.contains($0.value)
                        })
                Text(
                    "Missing details stay visible even after confirmation. Conflicts will need a choice before a plan can be applied."
                ).font(.footnote)
                Button("Stop using this brief") {
                    edit { $0.confirmed = false }
                    dismiss()
                }
            }.navigationTitle("Brand requirements").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
    private func edit(_ change: (inout MiraBrief) -> Void) {
        store.update(projectID, immediate: false) { p in
            change(&p.brief)
            p.brief.confirmed = false
            p.brief.revision += 1
            p.touch()
        }
    }
}

struct MiraConsentReviewView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        MiraPage {
            MiraSectionTitle(text: "AI data permission")
            Text(AIConsentCopy.purposeAndDestinations.replacingOccurrences(of: "ContentHelper", with: "Mira"))
            Text(
                "Saved local work and manual editing stay available if you decline. On-device microphone audio is not uploaded."
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
                get: { services.isAIConsentSheetPresented }, set: { services.setAIConsentSheetPresented($0) })
        ) {
            NavigationStack { MiraConsentReviewView() }
        }
    }
}
