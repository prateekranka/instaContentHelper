import PDFKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let message = UILabel()
    private let save = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private var brief: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.text = "Opening your brief…"
        save.setTitle("Save brief to Mira", for: .normal)
        save.isEnabled = false
        save.addTarget(self, action: #selector(saveBrief), for: .touchUpInside)
        close.setTitle("Close", for: .normal)
        close.addTarget(self, action: #selector(closeShare), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [message, save, close])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            save.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        Task { await loadBrief() }
    }

    private func loadBrief() async {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var parts: [String] = []
        for item in items {
            var attachments: [String] = []
            for provider in item.attachments ?? [] {
                let text: String?
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    text = await pdfText(provider)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    text = await plainText(provider)
                } else {
                    continue
                }
                if let text, hasText(text), !attachments.contains(text) { attachments.append(text) }
            }
            if let text = item.attributedContentText?.string, hasText(text), !attachments.contains(text) {
                attachments.insert(text, at: 0)
            }
            parts.append(contentsOf: attachments)
        }
        let text = parts.joined(separator: "\n\n")
        if hasText(text) {
            brief = text
            message.text = "Save this brief, then open Mira to read it in Deals."
            save.isEnabled = true
        } else {
            message.text = "There is no readable text. Copy the brief and paste it in Mira’s Deals tab."
        }
    }

    private func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func plainText(_ provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: String.self) {
            let text: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    continuation.resume(returning: text)
                }
            }
            if let text, hasText(text) { return text }
        }
        guard let identifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .plainText) == true
        }) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data.flatMap {
                    String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .utf16)
                })
            }
        }
    }

    private func pdfText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                continuation.resume(returning: url.flatMap { PDFDocument(url: $0)?.string })
            }
        }
    }

    @objc private func saveBrief() {
        guard let brief else { return }
        do {
            try MiraSharedBriefInbox.enqueue(brief)
            self.brief = nil
            save.isHidden = true
            message.text = "Saved to Mira. Open Mira to read the brief in Deals."
            close.setTitle("Done", for: .normal)
        } catch {
            message.text = "Mira could not save the brief. Try again, or paste the text in Deals."
        }
    }

    @objc private func closeShare() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
