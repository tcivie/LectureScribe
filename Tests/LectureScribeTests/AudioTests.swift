import AVFoundation
import CoreAudio
import Testing
@testable import LectureScribe

@Suite struct AudioLevelTests {
    @Test func pcmBufferLevel() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        #expect(rmsLevel(buffer) == 0)
        for channel in 0..<2 { for i in 0..<160 { buffer.floatChannelData![channel][i] = i.isMultiple(of: 2) ? 1 : -1 } }
        #expect(rmsLevel(buffer) == 1)
    }

    // The IOProc used to copy the AudioBufferList struct, which holds ONE inline
    // buffer; a multi-buffer device then read past the copy.
    @Test func bufferListLevelReadsEveryBuffer() {
        let frames = 64
        let loud = [Float](repeating: 0.5, count: frames)
        let quiet = [Float](repeating: 0, count: frames)
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        loud.withUnsafeBufferPointer { loudPtr in
            quiet.withUnsafeBufferPointer { quietPtr in
                let bytes = UInt32(frames * MemoryLayout<Float>.size)
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: UnsafeMutableRawPointer(mutating: loudPtr.baseAddress))
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: UnsafeMutableRawPointer(mutating: quietPtr.baseAddress))
                let expected = meterLevel(rms: (0.25 / 2).squareRoot())
                #expect(abs(bufferListLevel(list.unsafePointer) - expected) < 0.0001)
            }
        }
    }
}

@Suite struct SystemAudioFormatTests {
    func asbd(rate: Double, channels: UInt32, flags: AudioFormatFlags) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags, mBytesPerPacket: 4,
                                    mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
    }

    let planarFloat = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsPacked

    @Test func acceptsTheConfiguredFormat() {
        #expect(SystemAudio.isCompatible(asbd(rate: SystemAudio.sampleRate, channels: 2, flags: planarFloat), with: SystemAudio.format))
    }

    // A buffer in another shape is dropped instead of being copied as garbage.
    @Test func rejectsOtherShapes() {
        #expect(!SystemAudio.isCompatible(asbd(rate: 44_100, channels: 2, flags: planarFloat), with: SystemAudio.format))
        #expect(!SystemAudio.isCompatible(asbd(rate: SystemAudio.sampleRate, channels: 2, flags: kAudioFormatFlagIsFloat), with: SystemAudio.format))
        #expect(!SystemAudio.isCompatible(asbd(rate: SystemAudio.sampleRate, channels: 1, flags: planarFloat), with: SystemAudio.format))
    }

    @Test func audioOnlyConfigurationKeepsVideoTiny() {
        let config = SystemAudio.configuration()
        #expect(config.capturesAudio && config.excludesCurrentProcessAudio)
        #expect(config.width == 2 && config.height == 2)
        #expect(config.minimumFrameInterval.seconds >= 1)
    }
}

@Suite struct MicrophoneModeTests {
    @Test func namesMatchControlCenter() {
        #expect(MicrophoneModes.name(of: .voiceIsolation) == "Voice Isolation")
        #expect(MicrophoneModes.name(of: .wideSpectrum) == "Wide Spectrum")
        #expect(MicrophoneModes.name(of: .standard) == "Standard")
    }
}
