//
//  AddAccountView.swift
//  FastSM (iOS)
//
//  Add a Mastodon (instance → browser auth) or Bluesky (handle + app password)
//  account.
//

import SwiftUI
import FastSMCore

struct AddAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var platform: Platform = .mastodon
    @State private var server = ""
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var isWorking = false
    @State private var presentedError: PresentedError?

    private var canSubmit: Bool {
        guard !isWorking else { return false }
        switch platform {
        case .mastodon: return !server.trimmingCharacters(in: .whitespaces).isEmpty
        case .bluesky: return !handle.trimmingCharacters(in: .whitespaces).isEmpty && !appPassword.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Platform", selection: $platform) {
                        Text("Mastodon").tag(Platform.mastodon)
                        Text("Bluesky").tag(Platform.bluesky)
                    }
                    .pickerStyle(.segmented)
                }

                switch platform {
                case .mastodon:
                    Section {
                        TextField("mastodon.social", text: $server)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } header: {
                        Text("Server")
                    } footer: {
                        Text("You'll be taken to your server to sign in securely.")
                    }
                case .bluesky:
                    Section {
                        TextField("you.bsky.social", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("App password", text: $appPassword)
                    } header: {
                        Text("Bluesky")
                    } footer: {
                        Text("Create an app password in Bluesky settings — don't use your main password.")
                    }
                }

                if isWorking {
                    Section { HStack { ProgressView(); Text("Signing in…") } }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await submit() } }
                        .disabled(!canSubmit)
                }
            }
            .errorAlert($presentedError)
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch platform {
            case .mastodon:
                try await model.addMastodon(instance: server)
            case .bluesky:
                try await model.addBluesky(handle: handle, appPassword: appPassword)
            }
            dismiss()
        } catch {
            if !error.isCancellation {
                presentedError = ErrorPresenter.present(error, context: "Adding an account")
            }
        }
    }
}
