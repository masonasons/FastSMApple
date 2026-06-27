//
//  OAuthSession.swift
//  FastSMCore
//
//  Thin async wrapper around ASWebAuthenticationSession. Replaces FastSM's
//  out-of-band "paste the code" flow (mastodon_api.py) with a native, far more
//  accessible browser auth sheet that redirects back to the app.
//

import AuthenticationServices

/// Supplies the window/scene to anchor the auth sheet to. Each app provides one.
@MainActor
public protocol PresentationAnchorProviding: AnyObject {
    func presentationAnchor() -> ASPresentationAnchor
}

@MainActor
public final class OAuthSession: NSObject {
    private weak var anchorProvider: PresentationAnchorProviding?
    private var session: ASWebAuthenticationSession?

    public init(anchorProvider: PresentationAnchorProviding) {
        self.anchorProvider = anchorProvider
        super.init()
    }

    /// Present `url` and resolve with the callback URL once the system intercepts
    /// the `callbackScheme://` redirect. Throws `PlatformError.message` on
    /// cancellation or failure.
    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: PlatformError.message("Sign-in was canceled."))
                    } else {
                        continuation.resume(throwing: PlatformError.message(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: PlatformError.message("Sign-in returned no result."))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Use an ephemeral session so a stale browser login doesn't silently
            // reuse the wrong account.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: PlatformError.message("Couldn't start the sign-in session."))
            }
        }
    }
}

extension OAuthSession: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchorProvider?.presentationAnchor() ?? ASPresentationAnchor()
        }
    }
}
