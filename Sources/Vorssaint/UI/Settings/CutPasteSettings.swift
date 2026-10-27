// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct CutPasteSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = FinderCutPaste.shared
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderCutPasteShowHUD) private var showHUD = true
    @AppStorage(DefaultsKey.finderRenameEnabled) private var renameEnabled = false
    @AppStorage(DefaultsKey.finderRenameShortcut) private var renameShortcutRaw =
        GlobalShortcut.finderRenameDefault.storageValue
    @State private var renameError: String?
    @State private var recordingRename = false
    @State private var pendingRenameTakeOver: GlobalShortcut?
    @State private var menuConfiguration = FinderMenuConfigurationStore.shared.load()
    @State private var menuError: String?
    @State private var draggingMenuAction: FinderMenuAction?

    private var renameText: FinderRenameFeatureStrings {
        FeatureStrings.finderRename(l10n.language)
    }

    private var menuText: FinderMenuStrings {
        FeatureStrings.finderMenu(l10n.language)
    }

    private var renameShortcut: GlobalShortcut {
        GlobalShortcut(storageValue: renameShortcutRaw) ?? .finderRenameDefault
    }

    private var needsAccessibility: Bool {
        (AppFeature.finderCutPaste.isAvailable && enabled)
            || (AppFeature.finderRename.isAvailable && renameEnabled)
    }

    var body: some View {
        Form {
            if AppFeature.finderCutPaste.isAvailable {
                Section {
                    Toggle(l10n.s.cutPasteEnable, isOn: $enabled)
                        .onChange(of: enabled) { _, _ in
                            FinderCutPaste.shared.syncWithPreferences()
                        }
                    Text(l10n.s.cutPasteEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if enabled {
                        Toggle(l10n.s.cutPasteShowHUD, isOn: $showHUD)
                            .onChange(of: showHUD) { _, _ in
                                FinderCutPaste.shared.syncWithPreferences()
                            }
                        Text(l10n.s.cutPasteShowHUDCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if enabled, service.isRunning {
                        Label(l10n.s.cutPasteActiveNow, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .settingsFormSectionAnchor(.finderCutPaste)

                Section(l10n.s.cutPasteHowTitle) {
                    howRow(keys: ["⌘", "X"], text: l10n.s.cutPasteStep1)
                    howRow(keys: ["⌘", "V"], text: l10n.s.cutPasteStep2)
                    Text(l10n.s.cutPasteTextNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if AppFeature.finderContextMenu.isAvailable {
                Section {
                    Toggle(menuText.enableLabel, isOn: menuBinding(\.isEnabled))
                    Toggle(menuText.showIconsLabel, isOn: menuBinding(\.showIcons))
                    Text(menuText.extensionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let menuError {
                        Text(menuError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(menuText.sectionTitle)
                }
                .settingsFormSectionAnchor(.finderContextMenu)

                Section {
                    ForEach(menuConfiguration.items) { item in
                        if item.kind == .action, let action = item.action {
                            FinderMenuActionRow(
                                action: action,
                                title: menuText.title(for: action),
                                isEnabled: menuItemBinding(action),
                                isGloballyEnabled: menuConfiguration.isEnabled,
                                dragging: $draggingMenuAction,
                                reorderHint: menuText.reorderHint,
                                onMove: moveMenuAction
                            )
                        }
                    }
                } header: {
                    Text(menuText.itemsLabel)
                } footer: {
                    Text(menuText.reorderHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if AppFeature.finderRename.isAvailable {
                Section {
                    Toggle(renameText.enableLabel, isOn: $renameEnabled)
                        .onChange(of: renameEnabled) { _, _ in
                            FinderRenameService.shared.syncWithPreferences()
                        }
                    Text(renameText.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(renameText.shortcutLabel)
                        Spacer()
                        ShortcutRecorderButton(
                            shortcut: pendingRenameTakeOver ?? renameShortcut,
                            isEnabled: renameEnabled,
                            waitingTitle: l10n.s.shortcutPressKeys,
                            notCapturedAction: { renameError = l10n.s.shortcutNotCaptured },
                            recordingChanged: { recording in
                                recordingRename = recording
                                if recording {
                                    renameError = nil
                                    pendingRenameTakeOver = nil
                                }
                            },
                            invalidAction: { renameError = l10n.s.shortcutInvalid },
                            captureAction: saveRenameShortcut
                        )
                        .frame(width: 108)
                        .disabled(!renameEnabled)
                        Button(l10n.s.shortcutReset) {
                            renameShortcutRaw = GlobalShortcut.finderRenameDefault.storageValue
                            renameError = nil
                            pendingRenameTakeOver = nil
                            SystemShortcutTakeover.setTakeOver(DefaultsKey.finderRenameShortcut, false)
                            FinderRenameService.shared.syncWithPreferences()
                        }
                        .disabled(!renameEnabled || renameShortcut == .finderRenameDefault)
                    }
                    if let renameError {
                        Text(renameError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if recordingRename {
                        Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let pendingRenameTakeOver {
                        SystemShortcutTakeOverOffer(
                            shortcut: pendingRenameTakeOver,
                            onAccept: {
                                renameShortcutRaw = pendingRenameTakeOver.storageValue
                                SystemShortcutTakeover.setTakeOver(DefaultsKey.finderRenameShortcut, true)
                                self.pendingRenameTakeOver = nil
                                FinderRenameService.shared.syncWithPreferences()
                            },
                            onDismiss: {
                                self.pendingRenameTakeOver = nil
                                renameError = String(format: l10n.s.shortcutConflictFormat, "macOS")
                            }
                        )
                    }
                } header: {
                    Text(renameText.hubTitle)
                }
                .settingsFormSectionAnchor(.finderRename)
            }

            if needsAccessibility, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                    if AppFeature.finderCutPaste.isAvailable, enabled {
                        Text(l10n.s.cutPasteAutomationNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: l10n.language) { _, _ in renameError = nil }
    }

    private func menuBinding(_ keyPath: WritableKeyPath<FinderMenuConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { menuConfiguration[keyPath: keyPath] },
            set: { newValue in
                menuConfiguration[keyPath: keyPath] = newValue
                saveMenuConfiguration()
            }
        )
    }

    private func menuItemBinding(_ action: FinderMenuAction) -> Binding<Bool> {
        Binding(
            get: {
                menuConfiguration.items.first { $0.action == action }?.isEnabled ?? false
            },
            set: { newValue in
                if let index = menuConfiguration.items.firstIndex(where: { $0.action == action }) {
                    menuConfiguration.items[index].isEnabled = newValue
                } else {
                    menuConfiguration.items.append(.action(action, isEnabled: newValue))
                }
                saveMenuConfiguration()
            }
        )
    }

    private func moveMenuAction(_ source: FinderMenuAction, to target: FinderMenuAction) {
        let moved = withAnimation(.easeInOut(duration: 0.12)) {
            menuConfiguration.moveAction(source, to: target)
        }
        guard moved else { return }
        saveMenuConfiguration()
    }

    private func saveMenuConfiguration() {
        do {
            try FinderMenuConfigurationStore.shared.save(menuConfiguration)
            menuError = nil
            FinderMenuService.shared.syncWithPreferences()
        } catch {
            menuError = String(describing: error)
        }
    }

    private func howRow(keys: [String], text: String) -> some View {
        HStack(spacing: 10) {
            ShortcutCaps(keys: keys)
                .frame(width: 56, alignment: .leading)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveRenameShortcut(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: .finderRename) {
            renameError = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            renameError = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        // The offer is the last word on a combination: every other check has
        // already passed, so accepting it writes exactly what a save writes.
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut, for: .finderRename),
            takenOver: SystemShortcutTakeover.isTakenOver(DefaultsKey.finderRenameShortcut),
            current: GlobalShortcut(storageValue: renameShortcutRaw)) {
        case .offer:
            pendingRenameTakeOver = shortcut
            renameError = nil
            return
        case .save(let clearTakeOver):
            renameShortcutRaw = shortcut.storageValue
            renameError = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(DefaultsKey.finderRenameShortcut, false) }
        }
        FinderRenameService.shared.syncWithPreferences()
    }
}

private struct FinderMenuActionRow: View {
    let action: FinderMenuAction
    let title: String
    @Binding var isEnabled: Bool
    let isGloballyEnabled: Bool
    @Binding var dragging: FinderMenuAction?
    let reorderHint: String
    let onMove: (FinderMenuAction, FinderMenuAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
                .help(reorderHint)
                .onDrag {
                    dragging = action
                    return NSItemProvider(object: action.rawValue as NSString)
                }
            Image(systemName: action.defaultSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.callout)
            Spacer(minLength: 0)
            Toggle(title, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isGloballyEnabled)
        }
        .padding(.vertical, 2)
        .opacity(dragging == action ? 0.45 : 1)
        .onDrop(of: [UTType.text],
                delegate: FinderMenuActionDropDelegate(target: action,
                                                       dragging: $dragging,
                                                       onMove: onMove))
    }
}

private struct FinderMenuActionDropDelegate: DropDelegate {
    let target: FinderMenuAction
    @Binding var dragging: FinderMenuAction?
    let onMove: (FinderMenuAction, FinderMenuAction) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        onMove(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
