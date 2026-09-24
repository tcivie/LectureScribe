import AVFoundation

enum MicrophoneModes {
    static func name(of mode: AVCaptureDevice.MicrophoneMode) -> String {
        switch mode {
        case .standard: return "Standard"
        case .wideSpectrum: return "Wide Spectrum"
        case .voiceIsolation: return "Voice Isolation"
        @unknown default: return "Standard"
        }
    }

    static var activeName: String {
        name(of: AVCaptureDevice.activeMicrophoneMode)
    }

    static func showPicker() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
}
