import Foundation
import QuickChatCore

@MainActor
final class ChatModel: ObservableObject {
    struct Turn: Identifiable {
        let id = UUID()
        var question: String
        var answer = ""
        var reasoning = ""
        var error: String?
    }

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var isStreaming = false
    private var task: Task<Void, Never>?

    func send(_ text: String, store: Store) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }

        turns.append(Turn(question: question))
        let index = turns.count - 1

        guard let current = store.current else {
            turns[index].error = "No model yet. Open settings (⌘,) and paste a config or add an endpoint."
            return
        }

        // Earlier answered turns become context; failed ones are left out.
        var messages = [ChatMessage(role: "system", content: Self.systemPrompt(name: store.userName))]
        for turn in turns.dropLast() where !turn.answer.isEmpty {
            messages.append(ChatMessage(role: "user", content: turn.question))
            messages.append(ChatMessage(role: "assistant", content: turn.answer))
        }
        messages.append(ChatMessage(role: "user", content: question))

        let apiKey = store.apiKey(for: current.endpoint.id)
        isStreaming = true
        task = Task { [weak self] in
            do {
                let stream = ChatClient.stream(baseURL: current.endpoint.baseURL, apiKey: apiKey,
                                               model: current.model.id, effort: current.variant?.effort,
                                               messages: messages)
                for try await event in stream {
                    guard let self else { return }
                    switch event {
                    case .content(let c): self.turns[index].answer += c
                    case .reasoning(let r): self.turns[index].reasoning += r
                    }
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                self?.turns[index].error = error.localizedDescription
            }
            self?.isStreaming = false
        }
    }

    func stop() {
        task?.cancel()
        isStreaming = false
    }

    func clear() {
        stop()
        turns = []
    }

    private static func systemPrompt(name: String) -> String {
        var prompt = "You are QuickChat, a fast assistant inside a small menu-bar window on macOS. "
            + "Answer directly and keep it short unless the user asks for detail. Markdown is fine."
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { prompt += " The user's name is \(trimmed)." }
        return prompt
    }
}
