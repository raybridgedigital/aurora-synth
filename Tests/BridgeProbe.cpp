#include "AuroraBridge.h"
#include <chrono>
#include <cstring>
#include <iostream>
#include <thread>

// By default this only initializes MIDI and enumerates devices. --audio starts
// the current default output for one second without generating any notes.
int main(int argc, char **argv) {
    aurora_initialize();
    std::cout << "Audio outputs: " << aurora_audio_devices_json() << "\n"
              << "MIDI inputs: " << aurora_midi_sources_json() << "\n"
              << "Status: " << aurora_status() << "\n";
    int result = 0;
    if (argc > 1 && std::strcmp(argv[1], "--audio") == 0) {
        aurora_set_global(AGMaster, 0); // guarantee silence even if a physical keyboard is played
        if (!aurora_start_audio(0, 128)) { std::cerr << aurora_status() << "\n"; result = 1; }
        else {
            aurora_note_on(60, 90);
            std::this_thread::sleep_for(std::chrono::seconds(1));
            std::cout << "Audio running: " << aurora_audio_running()
                      << ", rate: " << aurora_sample_rate()
                      << ", buffer: " << aurora_buffer_frames()
                      << ", peak: " << aurora_output_peak()
                      << ", CPU: " << aurora_cpu_load()
                      << ", voices: " << aurora_active_voices() << "\n";
            if (!aurora_audio_running() || aurora_active_voices() == 0) result = 1;
            aurora_note_off(60);
        }
        aurora_stop_audio();
    }
    aurora_shutdown();
    return result;
}
