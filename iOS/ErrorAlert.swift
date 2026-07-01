//
//  ErrorAlert.swift
//  FastSM (iOS)
//
//  A reusable error alert: the specific summary as the title, the full detail as
//  the message, and a "Copy Details" button that puts the details on the
//  clipboard — instead of a generic "Something went wrong" with no way to capture
//  what happened.
//

import SwiftUI
import FastSMCore

extension View {
    /// Presents `error` as an alert when it becomes non-nil. Shows the specific
    /// summary and detail, and offers Copy Details / OK.
    func errorAlert(_ error: Binding<PresentedError?>) -> some View {
        let isPresented = Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )
        return alert(error.wrappedValue?.summary ?? "Error", isPresented: isPresented) {
            Button("Copy Details") {
                UIPasteboard.general.string = error.wrappedValue?.detail
                error.wrappedValue = nil
            }
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue?.detail ?? "")
        }
    }
}
