public actor DictationController {
    public private(set) var state: DictationState
    private var armedSpeechDetected = false

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
            await beginArmedCapture()

        case .activationThresholdPassed:
            guard state == .armed else {
                return
            }
            state = .recording(speechDetected: armedSpeechDetected)
            armedSpeechDetected = false

        case .triggerUp:
            await handleTriggerUp()

        case let .nonTriggerKeyDown(_, isModifierOnly):
            await handleNonTriggerKeyDown(isModifierOnly: isModifierOnly)

        case .escapeKeyDown:
            await cancelActiveHold()

        case .speechDetected:
            if state == .armed {
                armedSpeechDetected = true
            } else if case .recording = state {
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

    private func beginArmedCapture() async {
        armedSpeechDetected = false
        state = .armed
        do {
            try await fakeAudio.startRecording()
        } catch {
            guard state == .armed else {
                return
            }
            state = .error(.audioStartFailed)
        }
    }

    private func handleTriggerUp() async {
        switch state {
        case .armed:
            armedSpeechDetected = false
            state = .idle
            await fakeAudio.discardRecording()

        case .recording:
            await finishRecordingAndInsert()

        case .idle, .processing, .inserting, .error:
            return
        }
    }

    private func handleNonTriggerKeyDown(isModifierOnly: Bool) async {
        switch state {
        case .armed:
            armedSpeechDetected = false
            state = .idle
            await fakeAudio.discardRecording()

        case let .recording(speechDetected):
            if !speechDetected, !isModifierOnly {
                state = .idle
                await fakeAudio.discardRecording()
            }

        case .idle, .processing, .inserting, .error:
            return
        }
    }

    private func cancelActiveHold() async {
        switch state {
        case .armed:
            armedSpeechDetected = false
            state = .idle
            await fakeAudio.discardRecording()

        case .recording:
            state = .idle
            await fakeAudio.discardRecording()

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
