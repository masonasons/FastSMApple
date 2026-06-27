//
//  SettingsView.swift
//  FastSM (iOS)
//
//  App settings: how many pages to fetch and how many posts to cache per
//  timeline.
//

import SwiftUI
import FastSMCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var fetchPages: Int = 3
    @State private var cacheLimit: Int = 200
    @State private var soundsEnabled: Bool = true
    @State private var demojify: Bool = false
    @State private var enterToSend: Bool = false
    @State private var soundpack: String = AppSettings.defaultSoundpackName
    @State private var autoRefresh: Int = 0
    @State private var syncHomePosition: Bool = false
    @State private var streaming: Bool = false
    @State private var recordEveryNavStep: Bool = false

    private func autoRefreshLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Off"
        case 30: return "Every 30 seconds"
        case 60: return "Every minute"
        case 120: return "Every 2 minutes"
        case 300: return "Every 5 minutes"
        default: return "Every \(seconds)s"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Remove emojis from posts and names", isOn: $demojify)
                        .onChange(of: demojify) { _, value in model.updateDemojify(value) }
                    Toggle("Send posts with Return key", isOn: $enterToSend)
                        .onChange(of: enterToSend) { _, value in model.updateEnterToSend(value) }
                }

                Section("Speech") {
                    NavigationLink("What VoiceOver reads") { SpeechSettingsView() }
                }

                Section("Movement") {
                    NavigationLink("Movement units (rotors)") { MovementSettingsView() }
                }

                Section("Notifications") {
                    Text(model.pushStatus).font(.footnote)
                    if let endpoint = PushManager.shared.endpoint()?.absoluteString {
                        Text(endpoint).font(.caption2).textSelection(.enabled)
                    } else {
                        Text("No device token yet").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Re-register push") { model.enablePush() }
                }

                Section {
                    Toggle("Play sounds", isOn: $soundsEnabled)
                        .onChange(of: soundsEnabled) { _, value in model.updateSounds(value) }
                    Picker("Soundpack", selection: $soundpack) {
                        ForEach(AppModel.availableSoundpacks(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: soundpack) { _, value in model.updateSoundpack(value) }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("In the Files app, open On My iPhone → FastSM → Soundpacks and drop a soundpack folder in, then pick it here.")
                }

                Section {
                    Stepper("Posts cached: \(cacheLimit)",
                            value: $cacheLimit,
                            in: AppSettings.cacheLimitRange,
                            step: 250)
                        .onChange(of: cacheLimit) { _, value in model.updateCacheLimit(value) }
                    Picker("Auto-refresh", selection: $autoRefresh) {
                        ForEach(AppSettings.autoRefreshOptions, id: \.self) { secs in
                            Text(autoRefreshLabel(secs)).tag(secs)
                        }
                    }
                    .onChange(of: autoRefresh) { _, value in model.updateAutoRefresh(value) }
                    Toggle("Sync home position with Mastodon", isOn: $syncHomePosition)
                        .onChange(of: syncHomePosition) { _, value in model.updateSyncHomePosition(value) }
                    Toggle("Stream in real time (Mastodon)", isOn: $streaming)
                        .onChange(of: streaming) { _, value in model.updateStreaming(value) }
                    Toggle("Go Back remembers every step (not just jumps)", isOn: $recordEveryNavStep)
                        .onChange(of: recordEveryNavStep) { _, value in model.updateRecordEveryNavStep(value) }
                } header: {
                    Text("Timelines")
                } footer: {
                    Text("Posts kept on disk per timeline. Auto-refresh checks for new posts and plays each timeline's sound.")
                }

                Section {
                    Stepper("API calls when loading timelines: \(fetchPages)",
                            value: $fetchPages,
                            in: AppSettings.fetchPagesRange)
                        .onChange(of: fetchPages) { _, value in model.updateFetchPages(value) }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Each call fetches about 40 posts. Applies to refresh and scrollback.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                fetchPages = model.settingsFetchPages
                cacheLimit = model.settingsCacheLimit
                soundsEnabled = model.settingsSoundsEnabled
                demojify = model.settingsDemojify
                enterToSend = model.settingsEnterToSend
                soundpack = model.settingsSoundpack
                autoRefresh = model.settingsAutoRefresh
                syncHomePosition = model.settingsSyncHomePosition
                streaming = model.settingsStreaming
                recordEveryNavStep = model.settingsRecordEveryNavStep
            }
        }
    }
}
