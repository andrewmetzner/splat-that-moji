import KaomojiKit
import SwiftUI

/// What the picker can ask its controller to do.
@MainActor
struct PickerActions {
    var insert: (Kaomoji, InsertMode?, Bool?) -> Void
    var toggleFavorite: (Kaomoji) -> Void
    var openSettings: () -> Void
    var openAccessibilitySettings: () -> Void
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: UserLibrary
    @ObservedObject var store: KaomojiStore
    let actions: PickerActions

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            scopeBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 340)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { searchFocused = true }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.requestFocus()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            modeMenu
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var placeholder: String {
        guard let count = store.database?.entries.count else { return "Loading kaomoji…" }
        return "Search \(count.formatted()) kaomoji"
    }

    private var modeMenu: some View {
        Menu {
            Picker("Insert by", selection: $settings.insertMode) {
                ForEach(InsertMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Toggle("Escape for Markdown", isOn: $settings.escapeMarkdown)
        } label: {
            Text(settings.insertMode.title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .help("How the kaomoji gets into your app")
    }

    // MARK: Scope chips

    private var scopeBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.scopes) { scope in
                        ScopeChip(scope: scope, isSelected: scope == model.scope)
                            .id(scope.id)
                            .onTapGesture {
                                model.scope = scope
                                model.requestFocus()
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .onChange(of: model.scope) { _, scope in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(scope.id, anchor: .center) }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var content: some View {
        if store.database == nil {
            VStack(spacing: 10) {
                if let error = store.loadError {
                    Text("(╥﹏╥)").font(.system(size: 34))
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Loading kaomoji…").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.results.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: settings.columns),
                    spacing: 8
                ) {
                    ForEach(0..<min(model.visibleLimit, model.results.count), id: \.self) { i in
                        let kaomoji = model.results[i]
                        KaomojiCell(
                            kaomoji: kaomoji,
                            isSelected: i == model.selection,
                            isFavorite: library.isFavorite(kaomoji.text),
                            fontSize: settings.fontSize
                        )
                        .id(i)
                        .onTapGesture { actions.insert(kaomoji, nil, nil) }
                        .contextMenu { contextMenu(for: kaomoji) }
                        .onAppear { model.loadMore(near: i) }
                    }
                }
                .padding(12)
                .id(model.resultsVersion)
            }
            .onChange(of: model.selection) { _, i in proxy.scrollTo(i) }
            .onChange(of: model.resultsVersion) { proxy.scrollTo(0, anchor: .top) }
        }
    }

    @ViewBuilder
    private func contextMenu(for kaomoji: Kaomoji) -> some View {
        Button("Insert") { actions.insert(kaomoji, nil, nil) }
        Button("Insert Markdown-Escaped") { actions.insert(kaomoji, nil, true) }
        Button("Copy") { actions.insert(kaomoji, .copy, nil) }
        Divider()
        Button(library.isFavorite(kaomoji.text) ? "Remove from Favorites" : "Add to Favorites") {
            actions.toggleFavorite(kaomoji)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            switch (model.scope, model.query.isEmpty) {
            case (.favorites, true):
                Text("☆ﾐ(o*･ω･)ﾉ").font(.system(size: 30))
                Text("No favorites yet. Press ⌘D on any kaomoji to add it.").foregroundStyle(.secondary)
            case (.recents, true):
                Text("(・・ ) ?").font(.system(size: 30))
                Text("Kaomoji you use will show up here.").foregroundStyle(.secondary)
            default:
                Text("(´・ω・`)").font(.system(size: 30))
                Text("Nothing matches “\(model.query)”" + (model.scope == .all ? "" : " in \(model.scope.title)"))
                    .foregroundStyle(.secondary)
                if model.scope != .all {
                    Button("Search all kaomoji") { model.scope = .all }
                        .focusable(false)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let notice = model.notice {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(notice.message).font(.system(size: 12)).lineLimit(2)
                if notice.offersAccessibilitySettings {
                    Button("Open Settings…", action: actions.openAccessibilitySettings)
                        .controlSize(.small)
                        .focusable(false)
                }
                Spacer(minLength: 0)
            } else {
                if let kaomoji = model.selected {
                    Text(kaomoji.text)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(Self.distinctTags(kaomoji.tags).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if store.database != nil {
                    Text("\(model.results.count.formatted())")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                KeyHint(key: "↩", label: settings.insertMode.title)
                KeyHint(key: "⌘↩", label: "Copy")
                KeyHint(key: "⌘D", label: "Favorite")
                KeyHint(key: "⇥", label: "Category")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    /// The first few tags that each add a new word ("animals cat happy" after "cat", "happy" adds nothing).
    static func distinctTags(_ tags: [String], limit: Int = 5) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for tag in tags where result.count < limit {
            let words = tag.split(separator: " ").map { $0.hasSuffix("s") ? String($0.dropLast()) : String($0) }
            if words.contains(where: { !seen.contains($0) }) {
                result.append(tag)
                seen.formUnion(words)
            }
        }
        return result
    }
}

// MARK: - Pieces

struct KaomojiCell: View {
    let kaomoji: Kaomoji
    let isSelected: Bool
    let isFavorite: Bool
    let fontSize: Double
    @State private var isHovering = false

    var body: some View {
        Text(kaomoji.text)
            .font(.system(size: fontSize))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: fontSize * 2.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(isHovering ? 0.09 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .help(kaomoji.tags.prefix(8).joined(separator: ", "))
    }
}

struct ScopeChip: View {
    let scope: PickerScope
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = scope.symbol {
                Image(systemName: isSelected ? symbol + ".fill" : symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(scope.title)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07)))
        .contentShape(Capsule())
        .help(helpText)
    }

    private var helpText: String {
        if case .category(let c) = scope { return "\(c.icon)  \(c.count.formatted()) kaomoji" }
        return scope.title
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
