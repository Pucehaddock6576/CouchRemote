// MappingUI.swift — the action picker, shortcut recorder, Buttons tab and App Profiles tab
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Choosing an app

func chooseAppBundleID() -> String? {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return Bundle(url: url)?.bundleIdentifier
}

func appName(_ bid: String) -> String {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.deletingPathExtension().lastPathComponent ?? bid
}

func appIcon(_ bid: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

// MARK: - Shortcut recorder

struct KeyRecorder: View {
    @Binding var action: Action
    var id: String
    @ObservedObject private var ui = UIState.shared

    private var recording: Bool { ui.recordingID == id }

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press a shortcut…" : (action.keyCode.map { KeyNames.describe(code: $0, mods: CGEventFlags(rawValue: action.modifiers ?? 0)) } ?? "Record shortcut"))
                .frame(minWidth: 130)
        }
        .tint(recording ? .orange : nil)
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        ui.stopRecording()
        ui.recordingID = id
        let binding = $action
        ui.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            var f = CGEventFlags()
            if e.modifierFlags.contains(.command) { f.insert(.maskCommand) }
            if e.modifierFlags.contains(.option) { f.insert(.maskAlternate) }
            if e.modifierFlags.contains(.control) { f.insert(.maskControl) }
            if e.modifierFlags.contains(.shift) { f.insert(.maskShift) }
            binding.wrappedValue = Action(kind: .keystroke, keyCode: Int(e.keyCode), modifiers: f.rawValue)
            UIState.shared.stopRecording()
            return nil
        }
    }

    private func stop() { ui.stopRecording() }
}

// MARK: - Action editor (one row's "what it does")

struct ActionEditor: View {
    @Binding var action: Action
    var allowInherit: Bool
    var id: String

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ActionKind.categories, id: \.self) { cat in
                    let kinds = ActionKind.allCases.filter { $0.category == cat && (allowInherit || $0 != .inherit) }
                    if !kinds.isEmpty {
                        Section(cat) {
                            ForEach(kinds) { k in
                                Button(k.title) { action = Action(kind: k, keyCode: action.keyCode, modifiers: action.modifiers, text: k.param == .none ? nil : action.text) }
                            }
                        }
                    }
                }
            } label: {
                Text(action.kind.param == .none ? action.kind.title : action.kind.title.replacingOccurrences(of: "…", with: ""))
            }
            .frame(width: 210)

            switch action.kind.param {
            case .keys:
                KeyRecorder(action: $action, id: id)
            case .text:
                TextField(placeholder, text: Binding(get: { action.text ?? "" }, set: { action.text = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(action.kind == .appleScript || action.kind == .shell ? .system(.body, design: .monospaced) : .body)
            case .app:
                Button {
                    if let bid = chooseAppBundleID() { action.text = bid }
                } label: {
                    HStack {
                        if let bid = action.text, let img = appIcon(bid) { Image(nsImage: img).resizable().frame(width: 16, height: 16) }
                        Text(action.text.map(appName) ?? "Choose app…")
                    }
                }
            case .none:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
    }

    private var placeholder: String {
        switch action.kind {
        case .openURL: return "https://…"
        case .appleScript: return "tell application \"Music\" to playpause"
        case .shell: return "open ~/Movies"
        default: return "Text to type"
        }
    }
}

// MARK: - Buttons tab

struct ButtonsTab: View {
    @ObservedObject var store = ConfigStore.shared
    @Binding var profileID: UUID?

    private var profileIndex: Int? {
        let id = profileID ?? store.config.profiles.first?.id
        return store.config.profiles.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Editing", selection: Binding(get: { profileID ?? store.config.profiles.first?.id }, set: { profileID = $0 })) {
                    ForEach(store.config.profiles) { p in
                        Text(p.isGlobal ? "Global (every app)" : p.name).tag(Optional(p.id))
                    }
                }
                .frame(maxWidth: 360)
                Spacer()
                if let i = profileIndex, !store.config.profiles[i].isGlobal {
                    Text("Rows set to “Same as Global” use the Global setting.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let i = profileIndex {
                Form {
                    ForEach(["Buttons", "Touch surface"], id: \.self) { group in
                        Section(group) {
                            ForEach(Trigger.allCases.filter { $0.group == group }) { t in
                                HStack(alignment: .center) {
                                    Text(t.title).frame(width: 260, alignment: .leading)
                                    ActionEditor(action: binding(i, t), allowInherit: !store.config.profiles[i].isGlobal,
                                                 id: store.config.profiles[i].id.uuidString + t.rawValue)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private func binding(_ i: Int, _ t: Trigger) -> Binding<Action> {
        Binding(
            get: {
                guard store.config.profiles.indices.contains(i) else { return .k(.none) }
                let p = store.config.profiles[i]
                return p.mappings[t.rawValue] ?? .k(p.isGlobal ? .none : .inherit)
            },
            set: { new in
                guard store.config.profiles.indices.contains(i) else { return }
                if new.kind == .inherit { store.config.profiles[i].mappings[t.rawValue] = nil }
                else { store.config.profiles[i].mappings[t.rawValue] = new }
            })
    }
}

// MARK: - App Profiles tab

struct ProfilesTab: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject private var ui = UIState.shared
    var editButtons: (UUID) -> Void

    private var selection: UUID? {
        get { ui.profileSelection }
        nonmutating set { ui.profileSelection = newValue }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.config.profiles) { p in
                            let on = ui.profileSelection == p.id
                            Button { ui.profileSelection = p.id } label: {
                                HStack {
                                    if let bid = p.bundleIDs.first, let img = appIcon(bid) { Image(nsImage: img).resizable().frame(width: 20, height: 20) }
                                    else { Image(systemName: p.isGlobal ? "globe" : "square.dashed").frame(width: 20) }
                                    Text(p.isGlobal ? "Global" : p.name).lineLimit(1)
                                    Spacer()
                                    if !p.enabled { Text("off").font(.caption).foregroundStyle(on ? Color.white : Color.secondary) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor : Color.clear))
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }
                        .disabled(selectedIndex.map { store.config.profiles[$0].isGlobal } ?? true)
                    Spacer()
                }
                .buttonStyle(.borderless).padding(8)
            }
            .frame(minWidth: 220, maxWidth: 280)

            Group {
                if let i = selectedIndex { detail(i) } else { Text("Choose a profile").foregroundStyle(.secondary) }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
        .onAppear { if selection == nil { selection = store.config.profiles.first?.id } }
    }

    private var selectedIndex: Int? { store.config.profiles.firstIndex { $0.id == selection } }

    @ViewBuilder private func detail(_ i: Int) -> some View {
        let p = store.config.profiles[i]
        Form {
            if p.isGlobal {
                Text("The Global profile applies everywhere. App profiles only need the buttons you want to change.")
                    .foregroundStyle(.secondary)
            } else {
                TextField("Name", text: $store.config.profiles[i].name)
                Toggle("Profile is on", isOn: $store.config.profiles[i].enabled)
                Section("Apps that use this profile") {
                    ForEach(p.bundleIDs, id: \.self) { bid in
                        HStack {
                            if let img = appIcon(bid) { Image(nsImage: img).resizable().frame(width: 18, height: 18) }
                            Text(appName(bid)); Text(bid).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.config.profiles[i].bundleIDs.removeAll { $0 == bid } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Menu("Add running app") {
                            ForEach(runningApps(), id: \.0) { bid, name in
                                Button(name) { addApp(bid, to: i) }
                            }
                        }
                        .frame(width: 180)
                        Button("Choose app…") { if let bid = chooseAppBundleID() { addApp(bid, to: i) } }
                    }
                }
                Section("Touch surface") {
                    Picker("When this app is in front", selection: $store.config.profiles[i].touchMode) {
                        Text("Don't change mode").tag(TouchMode?.none)
                        ForEach(TouchMode.allCases) { m in Text(m.title).tag(TouchMode?.some(m)) }
                    }
                }
            }
            Section {
                Button("Edit this profile's buttons →") { editButtons(p.id) }
                if !p.isGlobal {
                    Button("Duplicate profile") {
                        var copy = p; copy.id = UUID(); copy.name += " copy"; copy.bundleIDs = []
                        store.config.profiles.append(copy); selection = copy.id
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runningApps() -> [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { a in a.bundleIdentifier.map { ($0, a.localizedName ?? $0) } }
            .sorted { $0.1 < $1.1 }
    }

    private func addApp(_ bid: String, to i: Int) {
        // an app can only belong to one profile
        for j in store.config.profiles.indices where j != i { store.config.profiles[j].bundleIDs.removeAll { $0 == bid } }
        if !store.config.profiles[i].bundleIDs.contains(bid) { store.config.profiles[i].bundleIDs.append(bid) }
        if store.config.profiles[i].name == "New profile" { store.config.profiles[i].name = appName(bid) }
    }

    private func add() {
        let p = Profile(name: "New profile")
        store.config.profiles.append(p)
        selection = p.id
    }

    private func remove() {
        guard let i = selectedIndex, !store.config.profiles[i].isGlobal else { return }
        store.config.profiles.remove(at: i)
        selection = store.config.profiles.first?.id
    }
}

// MARK: - Couch Menu tab

struct MenuTab: View {
    @ObservedObject var store = ConfigStore.shared
    var body: some View {
        Form {
            Section("Favourites (shown first in the Couch Menu)") {
                ForEach(store.config.settings.favourites, id: \.self) { bid in
                    HStack {
                        if let img = appIcon(bid) { Image(nsImage: img).resizable().frame(width: 20, height: 20) }
                        Text(appName(bid))
                        Spacer()
                        Button { move(bid, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                        Button { move(bid, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                        Button { store.config.settings.favourites.removeAll { $0 == bid } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                    }
                }
                Button("Add app…") {
                    if let bid = chooseAppBundleID(), !store.config.settings.favourites.contains(bid) { store.config.settings.favourites.append(bid) }
                }
            }
            Section("Menu contents") {
                Toggle("Show running apps (switch, hide, quit)", isOn: $store.config.settings.menuShowsRunningApps)
                Text("The menu also includes volume, play/pause, touch mode, Desktop actions, Files, sleep timer and Power.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Preview the Couch Menu") { CouchMenu.shared.toggle() }
                Text("On the remote: swipe up/down to move, click the touch surface to choose, Menu to go back, TV to close.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ bid: String, _ d: Int) {
        var f = store.config.settings.favourites
        guard let i = f.firstIndex(of: bid), f.indices.contains(i + d) else { return }
        f.swapAt(i, i + d)
        store.config.settings.favourites = f
    }
}
