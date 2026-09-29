"""Offline unit tests for tools/sfx.py's helpers (#95). The generation itself
talks to a paid, non-reproducible API and has no test.

Run from the repository root with `python3 -m unittest tools.test_sfx`
(test/tools/sfx_helpers_test.dart does, so the gate runs it). With
`--write-fixtures` it instead writes the audio guard's mutation fixtures to
test/fixtures/audio/, which are committed; `Fixtures` below holds the
committed bytes to what this writes.
"""
import math
import pathlib
import struct
import sys
import tempfile
import unittest
import wave

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import sfx  # noqa: E402

FIXTURES = sfx.ROOT / "test" / "fixtures" / "audio"
# name -> (seconds, channels): each breaks exactly one audio-guard rule when
# it replaces a clip -- stereo, an effect over 2 s, a loop under 29 s.
FIXTURE_SPECS = {
    "stereo.wav": (0.1, 2),
    "long_effect.wav": (2.5, 1),
    "short_loop.wav": (10.0, 1),
}


def write_fixtures(dest: pathlib.Path = FIXTURES) -> None:
    for name, (seconds, channels) in FIXTURE_SPECS.items():
        sfx.write_silence(dest / name, seconds, channels)


def pcm(*samples):
    return b"".join(struct.pack("<h", s) for s in samples)


class Helpers(unittest.TestCase):
    def test_peak_handles_the_negative_extreme(self):
        self.assertEqual(sfx._peak(pcm(0, 100, -300)), 300)
        self.assertEqual(sfx._peak(pcm(-32768, 5)), 32768)
        self.assertEqual(sfx._peak(b""), 0)

    def test_scale_clamps_and_ignores_an_odd_trailing_byte(self):
        self.assertEqual(sfx._scale(pcm(1000, -1000), 2.0), pcm(2000, -2000))
        self.assertEqual(sfx._scale(pcm(30000), 2.0), pcm(32767))
        self.assertEqual(sfx._scale(pcm(-30000), 2.0), pcm(-32768))
        self.assertEqual(sfx._scale(pcm(4) + b"\x01", 1.0), pcm(4) + b"\x00")

    def test_to_mono_averages_the_pair(self):
        self.assertEqual(sfx._to_mono(pcm(100, 300, -100, -300)), pcm(200, -200))
        self.assertEqual(sfx._to_mono(b""), b"")

    def test_polish_trims_leading_silence_cuts_fades_and_normalises(self):
        silence = pcm(*([0, 0] * 2205))  # 50 ms of stereo silence
        tone = pcm(*([8000, 8000, -8000, -8000] * 4410))  # 200 ms stereo
        out = sfx.polish(silence + tone, 0.1)
        self.assertLessEqual(len(out), int(0.1 * sfx.RATE) * 2)
        self.assertGreater(len(out), 0)
        # the head is no longer 50 ms of silence: sound within the pre-roll
        first = next(i for i in range(0, len(out), 2)
                     if struct.unpack_from("<h", out, i)[0] != 0)
        self.assertLessEqual(first // 2, int(0.005 * sfx.RATE) + 1)
        peak = sfx._peak(out)
        self.assertAlmostEqual(peak / 32767, 0.89, delta=0.02)
        # the last sample is faded to (near) nothing
        self.assertLess(abs(struct.unpack_from("<h", out, len(out) - 2)[0]), 400)
        self.assertEqual(sfx.polish(b"", 0.1), b"")

    def test_polish_caps_the_gain_of_a_quiet_take(self):
        quiet = pcm(*([100, 100, -100, -100] * 4410))
        out = sfx.polish(quiet, 0.1)
        self.assertLessEqual(sfx._peak(out), 800)

    def test_polish_loop_sets_the_absolute_level_and_keeps_the_length(self):
        stereo = pcm(*([1000, 1000, -1000, -1000] * 1000))
        out = sfx.polish_loop(stereo, -15.0)
        self.assertEqual(len(out), len(stereo) // 2)
        self.assertAlmostEqual(20 * math.log10(sfx._peak(out) / 32767), -15.0, delta=0.1)

    def test_finish_applies_the_mix_offset_after_normalising(self):
        tone = pcm(*([8000, 8000, -8000, -8000] * 4410))
        move = sfx.finish("move", tone)
        end = sfx.finish("end", tone)
        self.assertAlmostEqual(20 * math.log10(sfx._peak(end) / 32767), -1.0, delta=0.1)
        self.assertAlmostEqual(20 * math.log10(sfx._peak(move) / 32767), -7.0, delta=0.1)

    def test_write_wav_is_44100_mono_16_bit(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "a.wav"
            sfx.write_wav(path, pcm(1, -32768, 3))
            with wave.open(str(path), "rb") as w:
                self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()), (1, 2, 44100, 3))
                self.assertEqual(w.readframes(3), pcm(1, -32768, 3))
            sfx.write_wav(path, b"")
            with wave.open(str(path), "rb") as w:
                self.assertEqual(w.getnframes(), 0)

    def test_key_file_parsing(self):
        self.assertEqual(sfx.parse_key("ELEVENLABS_API_KEY=abc\n"), "abc")
        self.assertEqual(sfx.parse_key("export ELEVENLABS_API_KEY='abc'\n"), "abc")
        self.assertEqual(sfx.parse_key('# ELEVENLABS_API_KEY=no\nELEVENLABS_API_KEY = "x y"\n'), "x y")
        self.assertEqual(sfx.parse_key("OTHER=1\n"), "")
        self.assertEqual(sfx.parse_key(""), "")

    def test_the_six_clips_and_their_requests(self):
        self.assertEqual(list(sfx.SOUNDS) + list(sfx.MUSIC),
                         ["move", "capture", "castle", "check", "end", "music"])
        self.assertEqual(set(sfx.MIX_DB), set(sfx.SOUNDS))
        for name in sfx.SOUNDS:
            self.assertTrue(sfx.request_for(name)["text"].endswith(sfx.EFFECT_SUFFIX))
            self.assertNotIn("loop", sfx.request_for(name))
        self.assertEqual(sfx.request_for("move")["duration_seconds"], 0.5)
        self.assertEqual(sfx.request_for("end")["duration_seconds"], 1.4)
        music = sfx.request_for("music")
        self.assertTrue(music["loop"])
        self.assertNotIn(sfx.EFFECT_SUFFIX, music["text"])
        self.assertEqual(music["duration_seconds"], 30.0)
        self.assertEqual(music["prompt_influence"], 0.5)
        self.assertEqual(music["model_id"], sfx.MODEL)


class Fixtures(unittest.TestCase):
    def test_the_committed_fixtures_are_what_the_helper_writes(self):
        with tempfile.TemporaryDirectory() as d:
            write_fixtures(pathlib.Path(d))
            for name in FIXTURE_SPECS:
                self.assertEqual((FIXTURES / name).read_bytes(),
                                 (pathlib.Path(d) / name).read_bytes(), name)


if __name__ == "__main__":
    if sys.argv[1:] == ["--write-fixtures"]:
        write_fixtures()
    else:
        unittest.main()
