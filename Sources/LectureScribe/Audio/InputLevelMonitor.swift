import AVFoundation
import CoreAudio
import Foundation
import ScreenCaptureKit

@MainActor
final class InputLevelMonitor {
    struct Entry: Equatable {
        let kind: SourceKind
        let level: Float
    }

    static let shared = InputLevelMonitor()

    private var taps: [AudioDeviceID: DeviceTap] = [:]
    private var devices: [CoreAudioDevices.Device] = []
    private var defaultInput: AudioDeviceID?
    private let system = SystemAudioMeter()
    private var active = false
    private var listening = false
    private var micAllowed = false

    func start() {
        guard !active else { return }
        active = true
        listenForDeviceChanges()
        refresh()
        Task { await system.setRunning(true) }
        Task { await requestMicrophone() }
    }

    func stop() {
        guard active else { return }
        active = false
        taps.values.forEach { $0.close() }
        taps = [:]
        Task { await system.setRunning(false) }
    }

    func snapshot() -> [Entry] {
        let level = { (id: AudioDeviceID?) in id.flatMap { self.taps[$0]?.box.load() } ?? 0 }
        let fixed = [Entry(kind: .system, level: system.box.load()), Entry(kind: .microphone, level: level(defaultInput))]
        return fixed + devices.map { Entry(kind: .device(name: $0.name), level: level($0.id)) }
    }

    private func requestMicrophone() async {
        micAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        if !micAllowed { Log.engine("microphone permission denied — input meters stay dark") }
        refresh()
    }

    private func refresh() {
        devices = CoreAudioDevices.inputs()
        defaultInput = CoreAudioDevices.defaultDevice(output: false)
        let present = Set(devices.map(\.id))
        taps.filter { !present.contains($0.key) }.forEach { $0.value.close() }
        taps = taps.filter { present.contains($0.key) }
        guard active, micAllowed else { return }
        for device in devices where taps[device.id] == nil {
            taps[device.id] = DeviceTap(device: device.id)
        }
    }

    private func listenForDeviceChanges() {
        guard !listening else { return }
        listening = true
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = CoreAudioDevices.propertyAddress(selector)
            AudioObjectAddPropertyListenerBlock(CoreAudioDevices.systemObject, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
}

final class DeviceTap {
    let box = LevelBox()
    private let device: AudioDeviceID
    private var procID: AudioDeviceIOProcID?

    init?(device: AudioDeviceID) {
        self.device = device
        var created: AudioDeviceIOProcID?
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard AudioDeviceCreateIOProcID(device, meterIOProc, context, &created) == noErr, let created else { return nil }
        procID = created
        guard AudioDeviceStart(device, created) == noErr else {
            close()
            return nil
        }
    }

    func close() {
        guard let procID else { return }
        AudioDeviceStop(device, procID)
        AudioDeviceDestroyIOProcID(device, procID)
        self.procID = nil
    }

    deinit {
        close()
    }
}

private let meterIOProc: AudioDeviceIOProc = { _, _, input, _, _, _, context in
    guard let context else { return noErr }
    Unmanaged<LevelBox>.fromOpaque(context).takeUnretainedValue().store(bufferListLevel(input))
    return noErr
}

func bufferListLevel(_ list: UnsafePointer<AudioBufferList>) -> Float {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
    var power: Float = 0
    var channels: Float = 0
    for buffer in buffers {
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard let data = buffer.mData, count > 0 else { continue }
        let value = rms(data.assumingMemoryBound(to: Float.self), count: count)
        power += value * value
        channels += 1
    }
    return channels > 0 ? meterLevel(rms: (power / channels).squareRoot()) : 0
}

actor SystemAudioMeter {
    nonisolated let box = LevelBox()
    private var stream: SCStream?
    private var output: AudioSampleOutput?
    private var wanted = false
    private var busy = false
    private var retry: Task<Void, Never>?
    private let queue = DispatchQueue(label: "lecturescribe.meter", qos: .utility)

    func setRunning(_ running: Bool) async {
        wanted = running
        retry?.cancel()
        await reconcile()
    }

    private func reconcile() async {
        guard !busy, (stream != nil) != wanted else { return }
        busy = true
        let moved = await step()
        busy = false
        if moved { await reconcile() }
    }

    private func step() async -> Bool {
        wanted ? await open() : await close()
    }

    private func open() async -> Bool {
        do {
            let newStream = SCStream(filter: try await SystemAudio.displayFilter(), configuration: SystemAudio.configuration(), delegate: nil)
            let newOutput = AudioSampleOutput { [box] buffer in box.store(rmsLevel(buffer)) }
            try newStream.addStreamOutput(newOutput, type: .audio, sampleHandlerQueue: queue)
            try await newStream.startCapture()
            (stream, output) = (newStream, newOutput)
            return true
        } catch {
            Log.engine("system-output meter unavailable (\(error.localizedDescription)) — retrying")
            scheduleRetry()
            return false
        }
    }

    private func close() async -> Bool {
        try? await stream?.stopCapture()
        (stream, output) = (nil, nil)
        box.store(0)
        return true
    }

    private func scheduleRetry() {
        retry = Task {
            try? await Task.sleep(for: .seconds(MeterConfig.standard.retrySeconds))
            guard !Task.isCancelled else { return }
            await reconcile()
        }
    }
}
