//
//  SpeechSettingsView.swift
//  FastSM (iOS)
//
//  Choose what VoiceOver reads for posts and users: toggle fields on/off and
//  drag to reorder (Edit / VoiceOver reorder actions).
//

import SwiftUI
import FastSMCore

struct SpeechSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var status: [SpeechItem<StatusSpeechField>] = []
    @State private var user: [SpeechItem<UserSpeechField>] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                ForEach($status, id: \.field) { $item in
                    Toggle(item.field.displayName, isOn: $item.enabled)
                }
                .onMove { status.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Posts")
            } footer: {
                Text("Order top-to-bottom is the order VoiceOver speaks. Drag to reorder.")
            }

            Section("Users") {
                ForEach($user, id: \.field) { $item in
                    Toggle(item.field.displayName, isOn: $item.enabled)
                }
                .onMove { user.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .environment(\.editMode, .constant(.active))   // always reorderable
        .navigationTitle("Speech")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            status = model.speechSettings.status
            user = model.speechSettings.user
            loaded = true
        }
        .onChange(of: status) { _, _ in save() }
        .onChange(of: user) { _, _ in save() }
    }

    private func save() {
        guard loaded else { return }
        model.updateSpeech(SpeechSettings(status: status, user: user))
    }
}
