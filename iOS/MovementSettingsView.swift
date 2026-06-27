//
//  MovementSettingsView.swift
//  FastSM (iOS)
//
//  Choose which timeline-movement units appear as VoiceOver rotors, and in what
//  order. Toggle on/off and drag to reorder.
//

import SwiftUI
import FastSMCore

struct MovementSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var items: [MovementItem] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                ForEach($items, id: \.id) { $item in
                    Toggle(item.unit.title, isOn: $item.enabled)
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Each enabled unit becomes a VoiceOver rotor. Drag to reorder.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Movement")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            items = model.movementSettings.items
            loaded = true
        }
        .onChange(of: items) { _, _ in save() }
    }

    private func save() {
        guard loaded else { return }
        model.updateMovement(MovementSettings(items: items))
    }
}
