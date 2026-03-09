import Foundation
import SwiftUI

@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    @Published var entries: [Entry] = []

    private init() {}

    func log(_ message: String) {
        let entry = Entry(date: Date(), message: message)
        entries.append(entry)
        // Keep last 500 entries
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
        // Also print to console
        print(message)
    }

    nonisolated func send(_ message: String) {
        Task { @MainActor in
            self.log(message)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

struct DebugLogView: View {
    @ObservedObject var debugLog = DebugLog.shared
    @State private var autoScroll = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Debug Log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpokeTheme.textPrimary)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .foregroundStyle(SpokeTheme.textSecondary)
                Button("Clear") {
                    debugLog.clear()
                }
                .buttonStyle(SpokeGhostButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(SpokeTheme.divider).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(debugLog.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFormatter.string(from: entry.date))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(SpokeTheme.textTertiary)
                                    .frame(width: 85, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(SpokeTheme.textPrimary)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: debugLog.entries.count) { _, _ in
                    if autoScroll, let last = debugLog.entries.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(SpokeTheme.contentBg)
        .frame(minWidth: 500, minHeight: 350)
    }
}
