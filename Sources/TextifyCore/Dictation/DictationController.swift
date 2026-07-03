public actor DictationController {
    public private(set) var state: DictationState

    public let fakeAudio: FakeDictationAudio
    public let fakeTranscriber: FakeDictationTranscriber
    public let fakeInsertion: FakeDictationInsertion

    public init(
        state: DictationState = .idle,
        fakeAudio: FakeDictationAudio,
        fakeTranscriber: FakeDictationTranscriber,
        fakeInsertion: FakeDictationInsertion
    ) {
        self.state = state
        self.fakeAudio = fakeAudio
        self.fakeTranscriber = fakeTranscriber
        self.fakeInsertion = fakeInsertion
    }

    public static func fakingEverything(transcript: String = "") -> DictationController {
        DictationController(
            fakeAudio: FakeDictationAudio(),
            fakeTranscriber: FakeDictationTranscriber(transcripts: [transcript]),
            fakeInsertion: FakeDictationInsertion()
        )
    }

    public func handle(_ event: DictationEvent) async {
        switch event {
        case .triggerDown:
            guard state == .idle else {
                return
            }
            state = .armed

        case .activationThresholdPassed:
            guard state == .armed else {
                return
            }
            do {
                try await fakeAudio.startRecording()
                state = .recording(speechDetected: false)
            } catch {
                state = .error(.audioStartFailed)
            }

        case .triggerUp:
            await handleTriggerUp()

        case let .nonTriggerKeyDown(_, isModifierOnly):
            await handleNonTriggerKeyDown(isModifierOnly: isModifierOnly)

        case .escapeKeyDown:
            await cancelActiveHold()

        case .speechDetected:
            if case .recording = state {
                state = .recording(speechDetected: true)
            }
        }
    }

    public func runDevelopmentMockCycle() async {
        await handle(.triggerDown(timestampMs: 0))
        await handle(.activationThresholdPassed(timestampMs: 250))
        await handle(.speechDetected(timestampMs: 400))
        await handle(.triggerUp(timestampMs: 900))
    }

    private func handleTriggerUp() async {
        switch state {
        case .armed:
            state = .idle

        case let .recording(speechDetected):
            if speechDetected {
                await finishRecordingAndInsert()
            } else {
                await fakeAudio.discardRecording()
                state = .idle
            }

        case .idle, .processing, .inserting, .error:
            return
        }
    }

    private func handleNonTriggerKeyDown(isModifierOnly: Bool) async {
        guard !isModifierOnly else {
            return
        }

        switch state {
        case .armed:
            state = .idle

        case let .recording(speechDetected):
            if !speechDetected {
                await fakeAudio.discardRecording()
                state = .idle
            }

        case .idle, .processing, .inserting, .error:
            return
        }
    }

    private func cancelActiveHold() async {
        switch state {
        case .armed:
            state = .idle

        case .recording:
            await fakeAudio.discardRecording()
            state = .idle

        case .idle, .processing, .inserting, .error:
            return
        }
    }

    private func finishRecordingAndInsert() async {
        do {
            state = .processing
            let clip = try await fakeAudio.finishRecording()
            let transcript = try await fakeTranscriber.transcribe(clip)

            guard !transcript.isEmpty else {
                state = .idle
                return
            }

            state = .inserting
            try await fakeInsertion.insert(transcript)
            state = .idle
        } catch let error as DictationError {
            state = .error(error)
        } catch {
            state = .error(.transcriptionFailed)
        }
    }
}
