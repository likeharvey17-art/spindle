import AudioToolbox
import CoreAudio
import Foundation
import os

/// Measures how loud the Mac's audio output is, to drive the panel's VU meter.
///
/// Uses a Core Audio process tap (macOS 14.2+) on all system output. Nothing is
/// recorded or stored: each buffer is reduced to one RMS number and dropped.
/// It only runs while the meter is on screen.
final class AudioMeter: ObservableObject {
    /// Needle position, 0 (rest) … 1 (full scale), with VU-style ballistics.
    @Published private(set) var level: Double = 0
    @Published private(set) var available = true

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var timer: Timer?
    private let peak = OSAllocatedUnfairLock(initialState: Float(0))
    /// Creating the tap can wait on the audio-capture permission prompt, so all
    /// Core Audio setup and teardown runs here, never on the main thread.
    private let queue = DispatchQueue(label: "spindle.audiometer")
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        queue.async { [weak self] in
            let ok = self?.setUp() ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.running else { return }
                if ok { self.startNeedle() } else { self.available = false }
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        level = 0
        queue.async { [weak self] in self?.tearDown() }
    }

    deinit {
        timer?.invalidate()
        tearDown()
    }

    /// Builds the tap and its private aggregate device; runs on `queue`.
    private func setUp() -> Bool {
        guard tapID == kAudioObjectUnknown else { return true }
        guard #available(macOS 14.2, *) else { return false }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Spindle meter"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { tearDown(); return false }
        tapID = tap

        guard let outputUID = Self.defaultOutputUID() else { tearDown(); return false }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spindle meter",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else { tearDown(); return false }
        aggregateID = device

        let peak = self.peak
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            var sum: Float = 0
            var count = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                for i in 0..<n { sum += samples[i] * samples[i] }
                count += n
            }
            guard count > 0 else { return }
            let rms = (sum / Float(count)).squareRoot()
            peak.withLock { $0 = max($0, rms) }
        }
        guard status == noErr, let proc else { tearDown(); return false }
        procID = proc
        guard AudioDeviceStart(device, proc) == noErr else { tearDown(); return false }
        return true
    }

    private func startNeedle() {
        // ~30 updates a second with VU ballistics: quick rise, slower fall.
        var last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let dt = now.timeIntervalSince(last)
            last = now
            let rms = Double(self.peak.withLock { value -> Float in defer { value = 0 }; return value })
            // Map roughly −42 dBFS (rest) … −6 dBFS (full scale) onto the needle.
            let db = rms > 0 ? 20 * log10(rms) : -100
            let target = min(max((db + 42) / 36, 0), 1)
            let tau = target > self.level ? 0.09 : 0.32
            self.level += (target - self.level) * (1 - exp(-dt / tau))
        }
    }

    /// Releases the tap and device; runs on `queue` (or at deinit).
    private func tearDown() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
