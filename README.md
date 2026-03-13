# IRL Alert

The Enhanced IRL Alert App solves a critical problem for mobile In-Real-Life (IRL) streamers: missing stream interactions because mobile operating systems often suspend background web browsers, breaking existing WebSocket alert relies. 

Built natively in Swift and SwiftUI to leverage Apple's `AVAudioSession` and background execution APIs, the app connects directly to major alert services (such as Streamlabs and Twitch) via direct OAuth or by natively parsing Browser Source URLs. When an alert—such as a donation, follow, subscription, host, or raid—is triggered, the app reliably catches it even if the device screen is locked or the predominant streaming app (like IRL Pro) is active.

The app acts as an intelligent audio mixing companion. Instead of a visual overlay, it employs a strict FIFO (First-In, First-Out) queuing system to process alerts sequentially, preventing audio overlap. It fetches the required alert sounds, utilizes the device's native Text-to-Speech (TTS) to read out custom alert messages, and mixes this audio seamlessly into the streamer's earpiece alongside their primary stream audio. Additionally, the app features auto-reconnection with exponential backoff for unstable mobile networks, providing a robust, uninterrupted connection to the streamer’s community while out in the real world.
