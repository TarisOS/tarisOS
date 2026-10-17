---
name: audio
description: >
  Sound on this TarisOS Mac: the built-in speakers and their protection, headphones, the
  microphone, spatial audio, volume, output and input devices, Bluetooth audio, and PipeWire or
  WirePlumber settings. Triggers: sound, audio, speakers, headphones, microphone, mic, volume,
  spatial audio, surround, bass, equalizer, Bluetooth headphones, AirPods, PipeWire, WirePlumber,
  pactl, wpctl, no sound, crackling.
---

# Audio

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

## The speakers: never bypass their protection

A MacBook's speakers are driven through Asahi Linux's processing (`asahi-audio`), which shapes the
sound for them, and `speakersafetyd`, which keeps them from overheating. Without either, the
speakers can be damaged. Never:

- stop or disable `speakersafetyd`, or change its limits;
- send sound to the speakers' raw device or around Asahi's processing (a "raw" or "pro audio"
  profile, ALSA directly, another DSP in front of them);
- raise volume limits or apply generic Linux speaker "fixes" written for other laptops.

A sound problem on the speakers is checked, not worked around:
`systemctl status speakersafetyd`, `journalctl -b -u speakersafetyd`.

## Everyday settings

- **Volume and devices:** the volume keys, the bar's audio controls, Settings > Audio. From a
  terminal: `wpctl status`, `wpctl set-default <id>`, `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+`.
- **Microphone:** "Built-in Microphone" is the one to use: a mono copy of the Mac's microphone
  array, so apps recording in stereo get it on both sides.
- **Bluetooth:** Settings > Connected devices (or `bluetoothctl`).

## Spatial audio

On by default; switched in Settings > Audio, or
`wpctl settings --save taris.spatial-audio true|false`.

- **Built-in speakers** of the MacBook Air and MacBook Pro (M1 and M2): crosstalk cancellation,
  which spreads the sound past the edges of the laptop. The Mac mini's single speaker has nothing
  to cancel.
- **Headphones** (the jack, Bluetooth, USB): the two channels as two speakers in front of the
  listener.
- The speakers also get a little more bass, on or off.

## The user's own settings

PipeWire and WirePlumber settings of the user's own go in `~/.config/pipewire/` and
`~/.config/wireplumber/wireplumber.conf.d/`; never in `/usr/share/`. Nothing there may change the
speakers' processing chain (above). After a change: `systemctl --user restart wireplumber pipewire
pipewire-pulse`, then check `journalctl --user -b -u wireplumber`.

## No sound

1. The right output, not muted: `wpctl status`.
2. The services: `systemctl --user status pipewire wireplumber`, `systemctl status speakersafetyd`.
3. Their logs: `journalctl --user -b -u wireplumber -u pipewire`.
