package com.honestarcade.chess

import android.content.Context
import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// lib/feedback/sound_player.dart's soundChannelName is the same.
private const val SOUND_CHANNEL = "honestchess/sound"

private const val MUSIC = "music"

/**
 * The game's sounds (#96), ported from Honest Solitaire's SoundBridge. No
 * plugin: the audio plugins either pull in networking or a media player
 * this does not need, and no permission is needed.
 *
 * `load` takes {clip name: Flutter asset key} and answers how many opened;
 * the clip named `music` opens in a looping MediaPlayer, the rest in a
 * SoundPool. `play` takes a clip name and ignores one that has not finished
 * loading; `musicStart` answers whether the loop started, a second after
 * the latest effect at the earliest (it never starts
 * while another app is playing audio, and never takes audio focus, so it
 * never interrupts the player's own audio — owner, round one); `musicPause`
 * holds the position; `musicStop` resets it; `release` frees everything.
 * Usage is USAGE_GAME, so the media volume applies and the ringer switch
 * does not (owner, round one).
 */
class SoundBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val assets: AssetManager = context.assets
    private var pool: SoundPool? = null
    private var music: MediaPlayer? = null
    private var musicDead = false
    private val ids = mutableMapOf<String, Int>()
    private val ready = mutableSetOf<Int>()
    private var lastEffectAt = 0L
    private val main = Handler(Looper.getMainLooper())
    private var waitingStart: Runnable? = null
    private var waitingResult: MethodChannel.Result? = null

    /** Listens on the sound channel of [messenger]. */
    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, SOUND_CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val clips = call.arguments as? Map<*, *>
                if (clips == null) {
                    result.error("bad-args", "load takes {clip: asset}", null)
                    return
                }
                result.success(load(clips))
            }
            "play" -> {
                val id = ids[call.arguments as? String]
                if (id != null && id in ready) {
                    pool?.play(id, 1f, 1f, 1, 0, 1f)
                    lastEffectAt = SystemClock.uptimeMillis()
                }
                result.success(null)
            }
            "musicStart" -> musicStart(result)
            "musicPause" -> {
                pauseMusic()
                result.success(null)
            }
            "musicStop" -> {
                stopMusic()
                result.success(null)
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun load(clips: Map<*, *>): Int {
        release()
        val effects = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val next = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(effects)
            .build()
        next.setOnLoadCompleteListener { _, id, status ->
            if (status == 0) ready.add(id)
        }
        pool = next
        val loader = FlutterInjector.instance().flutterLoader()
        var opened = 0
        for ((name, asset) in clips) {
            if (name !is String || asset !is String) continue
            try {
                assets.openFd(loader.getLookupKeyForAsset(asset)).use { fd ->
                    if (name == MUSIC) {
                        val player = MediaPlayer()
                        player.setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_GAME)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build()
                        )
                        player.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                        player.isLooping = true
                        player.setOnErrorListener { _, _, _ ->
                            musicDead = true
                            true
                        }
                        player.prepare()
                        music = player
                    } else {
                        ids[name] = next.load(fd, 1)
                    }
                }
                opened++
            } catch (e: java.io.IOException) {
                // Skipped; the count tells the Dart side.
            } catch (e: IllegalStateException) {
                musicDead = true
            }
        }
        return opened
    }

    /**
     * Answers [result] with whether the loop started. One of this app's own
     * effects in the last second would read as "music active", so the check
     * waits until a second after the latest one — never skipped. The wait
     * is posted, not slept: this runs on the main thread, which must keep
     * taking touches and drawing (#145). A newer start, a pause, a stop or
     * a release ends a waiting start, which answers false.
     */
    private fun musicStart(result: MethodChannel.Result) {
        endWaitingStart()
        waitingResult = result
        startAfterEffects()
    }

    private fun startAfterEffects() {
        val since = SystemClock.uptimeMillis() - lastEffectAt
        if (since < 1000L) {
            val retry = Runnable { startAfterEffects() }
            waitingStart = retry
            main.postDelayed(retry, 1000L - since)
            return
        }
        waitingStart = null
        val result = waitingResult ?: return
        waitingResult = null
        result.success(startNow())
    }

    private fun endWaitingStart() {
        waitingStart?.let { main.removeCallbacks(it) }
        waitingStart = null
        waitingResult?.success(false)
        waitingResult = null
    }

    /** Starts the loop unless another app is playing audio. */
    private fun startNow(): Boolean {
        val player = music ?: return false
        if (musicDead) return false
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (player.isPlaying) return true
        if (manager != null && manager.isMusicActive) return false
        return try {
            player.start()
            true
        } catch (e: IllegalStateException) {
            musicDead = true
            false
        }
    }

    /** Holds the loop where it is; the activity calls this in onPause too. */
    fun pauseMusic() {
        endWaitingStart()
        val player = music ?: return
        try {
            if (player.isPlaying) player.pause()
        } catch (e: IllegalStateException) {
            musicDead = true
        }
    }

    private fun stopMusic() {
        endWaitingStart()
        val player = music ?: return
        try {
            if (player.isPlaying) player.pause()
            player.seekTo(0)
        } catch (e: IllegalStateException) {
            musicDead = true
        }
    }

    /** Frees the pool and the loop; safe to call twice. */
    fun release() {
        endWaitingStart()
        pool?.release()
        pool = null
        ids.clear()
        ready.clear()
        music?.release()
        music = null
        musicDead = false
    }
}
