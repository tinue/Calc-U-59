import SwiftUI

struct CardPickerView: View {
    enum Mode { case load, save }

    let mode: Mode
    let directory: URL
    let defaultFileName: String
    let onPick: (URL) -> Void

    @State private var fileName: String
    @State private var files: [String] = []
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, directory: URL, defaultFileName: String, onPick: @escaping (URL) -> Void) {
        self.mode = mode
        self.directory = directory
        self.defaultFileName = defaultFileName
        self.onPick = onPick
        _fileName = State(initialValue: defaultFileName)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack {
                Text(mode == .load ? "Load Card" : "Save Card")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // ── Filename field (save mode) ────────────────────────────────────
            if mode == .save {
                TextField("Filename", text: $fileName)
                    .textFieldStyle(.roundedBorder)
                    .padding([.horizontal, .top])
            }

            // ── File list ─────────────────────────────────────────────────────
            if files.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(mode == .load ? "No cards found" : "No existing cards")
                        .foregroundStyle(.secondary)
                    Text(directory.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List(files, id: \.self) { name in
                    Button {
                        if mode == .save {
                            fileName = name
                        } else {
                            onPick(directory.appendingPathComponent(name))
                            dismiss()
                        }
                    } label: {
                        Label(name, systemImage: "doc")
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────────
            HStack {
                Text(directory.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if mode == .save {
                    Button("Save") {
                        var name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.contains(".") { name += ".U59" }
                        onPick(directory.appendingPathComponent(name))
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(minWidth: 320, minHeight: 300)
        .onAppear { reload() }
    }

    private func reload() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )) ?? []
        files = urls
            .filter {
                let name = $0.lastPathComponent
                let ext = ($0.pathExtension).lowercased()
                return !name.hasSuffix(".icloud") && (ext == "u59" || ext == "bin")
            }
            .map { $0.lastPathComponent }
            .sorted()
    }
}
