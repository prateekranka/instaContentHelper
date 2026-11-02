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
                    Text("\(script.language) · Estimated runtime: \(script.durationSeconds) seconds").font(
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
                    Text("Spoken words stay separate from filming instructions. Runtime is an estimate.")
                        .font(.footnote)
                    Stepper(
                        "Runtime estimate: \(script.durationSeconds) seconds",
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
