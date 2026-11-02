// TaskAI.swift
// On-device step suggestions via Apple's Foundation Models framework. Nothing leaves
// the Mac — no network call, no API key, no per-use cost — which is the only reason
// this is worth doing in an app that otherwise treats "real signals only, never
// fabricated" as a hard rule (see NextMoveEngine). isAvailable can be false on Macs
// that don't support Apple Intelligence, or if it isn't enabled in System Settings —
// callers should hide/disable the feature rather than show an error in that case.

import Foundation
import FoundationModels

enum TaskAI {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    @Generable
    struct StepSuggestions {
        @Guide(description: "3 to 5 short, concrete, immediately actionable steps for completing the task. Each step should be specific, not a vague restatement of the task itself.")
        let steps: [String]
    }

    static func suggestSteps(title: String, notes: String) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
        You break a single task into a short list of concrete, actionable steps. Steps \
        must be specific enough to act on immediately. Keep each step under 8 words. \
        Never invent specifics that weren't implied by the task — if the task is vague, \
        keep the steps general rather than making things up.
        """)
        let prompt = notes.isEmpty ? title : "\(title)\n\(notes)"
        let response = try await session.respond(to: prompt, generating: StepSuggestions.self)
        return response.content.steps
    }
}
