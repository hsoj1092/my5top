package com.my5top.commute

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

object CommuteAlertHelper {
    const val CHANNEL_LIVE_RIDE = "my5top_live_ride"
    const val CHANNEL_STOP_ALERT = "my5top_stop_alert"
    const val CHANNEL_TRACK_ALERT = "my5top_track_alert"
    const val CHANNEL_ARRIVAL_ALARM = "my5top_arrival_alarm"

    const val NOTIF_ID_LIVE_RIDE = 5001

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioLock = Any()
    private var activeMediaPlayer: MediaPlayer? = null
    private var activeStopRunnable: Runnable? = null
    private var activeFocusRequest: AudioFocusRequest? = null
    private var activeNoisyReceiver: BroadcastReceiver? = null
    private var activeAudioAppContext: Context? = null

    fun ensureNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val rideChannel = NotificationChannel(
                CHANNEL_LIVE_RIDE,
                "Live Ride Progress",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent live train stop countdown & ETA"
                setShowBadge(false)
            }

            val stopChannel = NotificationChannel(
                CHANNEL_STOP_ALERT,
                "Stop Countdown Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts per stop or when X stops away from destination"
                enableVibration(true)
            }

            val trackChannel = NotificationChannel(
                CHANNEL_TRACK_ALERT,
                "Track Assignment Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Immediate alert when your NJ Transit track number is posted"
                enableVibration(true)
            }

            val arrivalChannel = NotificationChannel(
                CHANNEL_ARRIVAL_ALARM,
                "Destination Wake-Up Alarm",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Urgent wake-up alert when approaching your destination station"
                enableVibration(true)
            }

            nm.createNotificationChannels(
                listOf(rideChannel, stopChannel, trackChannel, arrivalChannel)
            )
        }
    }

    fun createLaunchPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    fun buildOngoingProgressNotification(
        context: Context,
        title: String,
        body: String,
        subText: String,
        passedStops: Int,
        totalStops: Int,
        stopActionLabel: String? = null,
        stopActionPendingIntent: PendingIntent? = null,
        indeterminate: Boolean = false
    ): Notification {
        ensureNotificationChannels(context)
        val safeTotal = if (totalStops < 1) 1 else totalStops
        val safePassed = passedStops.coerceIn(0, safeTotal)

        val builder = NotificationCompat.Builder(context, CHANNEL_LIVE_RIDE)
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSubText(subText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(createLaunchPendingIntent(context))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)

        if (!indeterminate) {
            builder.setProgress(safeTotal, safePassed, false)
        }

        if (stopActionLabel != null && stopActionPendingIntent != null) {
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                stopActionLabel,
                stopActionPendingIntent
            )
        }

        return builder.build()
    }

    fun showRideProgressNotification(
        context: Context,
        title: String,
        body: String,
        subText: String,
        passedStops: Int,
        totalStops: Int
    ) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notif = buildOngoingProgressNotification(
                context = context,
                title = title,
                body = body,
                subText = subText,
                passedStops = passedStops,
                totalStops = totalStops
            )
            nm.notify(NOTIF_ID_LIVE_RIDE, notif)
        } catch (_: Throwable) {}
    }

    fun cancelRideProgressNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIF_ID_LIVE_RIDE)
        } catch (_: Throwable) {}
    }

    /**
     * Returns true ONLY when personal headphones / earbuds / headset (wired, USB,
     * Bluetooth A2DP/SCO, BLE Headset, or Hearing Aid) are actively connected as
     * audio outputs. Never returns true for phone speakers or earpiece.
     */
    fun isHeadphonesConnected(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val outputs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (dev in outputs) {
                    val type = dev.type
                    if (type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                        type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        type == AudioDeviceInfo.TYPE_USB_HEADSET
                    ) {
                        return true
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                        type == AudioDeviceInfo.TYPE_HEARING_AID
                    ) {
                        return true
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        type == AudioDeviceInfo.TYPE_BLE_HEADSET
                    ) {
                        return true
                    }
                }
                false
            } else {
                @Suppress("DEPRECATION")
                am.isWiredHeadsetOn || am.isBluetoothA2dpOn || am.isBluetoothScoOn
            }
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Returns true when the phone would otherwise silence notification audio
     * (Ringer Mode Vibrate or Silent, notification stream volume 0, or DND).
     */
    fun isPhoneSilentOrVibrate(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
            val ringer = am.ringerMode
            if (ringer == AudioManager.RINGER_MODE_SILENT ||
                ringer == AudioManager.RINGER_MODE_VIBRATE
            ) {
                return true
            }
            if (am.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0) {
                return true
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                val filter = nm?.currentInterruptionFilter ?: NotificationManager.INTERRUPTION_FILTER_ALL
                if (filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
                    filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
                ) {
                    return true
                }
            }
            false
        } catch (_: Throwable) {
            false
        }
    }

    fun showCommuteAlertNotification(
        context: Context,
        id: Int,
        type: String,
        title: String,
        body: String,
        vibrate: Boolean,
        headphoneAudioBypass: Boolean = true
    ) {
        try {
            ensureNotificationChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = when (type) {
                "track" -> CHANNEL_TRACK_ALERT
                "arrival" -> CHANNEL_ARRIVAL_ALARM
                else -> CHANNEL_STOP_ALERT
            }

            val soundUri = if (type == "arrival") {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }

            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setSound(soundUri)
                .setContentIntent(createLaunchPendingIntent(context))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)

            nm.notify(id, builder.build())

            if (vibrate) {
                triggerVibration(context, type)
            }

            // Headphone-only sound bypass: IF AND ONLY IF toggle is ON, headphones are connected,
            // alert is actionable (not passive 'info'), and phone is currently on Vibrate/Silent/DND.
            if (headphoneAudioBypass &&
                type != "info" &&
                isPhoneSilentOrVibrate(context) &&
                isHeadphonesConnected(context)
            ) {
                playHeadphoneBypassSound(context, type)
            }
        } catch (_: Throwable) {}
    }

    /**
     * Plays the alert tone strictly via AudioAttributes.USAGE_MEDIA while headphones
     * are connected, briefly ducking background music, and immediately halting if
     * ACTION_AUDIO_BECOMING_NOISY fires (headphone disconnect) so sound never leaks
     * to phone speakers.
     */
    private fun playHeadphoneBypassSound(context: Context, type: String) {
        val appCtx = context.applicationContext
        val am = appCtx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return

        // Final safety check right before audio playback
        if (!isHeadphonesConnected(appCtx)) return

        val soundUri = if (type == "arrival") {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        } else {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        } ?: return

        val maxDurationMs = if (type == "arrival") 3600L else 2400L

        mainHandler.post {
            synchronized(audioLock) {
                releaseActiveHeadphonePlayerLocked()

                if (!isHeadphonesConnected(appCtx)) return@synchronized

                val audioAttrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val focusReq = AudioFocusRequest.Builder(
                            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                        )
                            .setAudioAttributes(audioAttrs)
                            .setWillPauseWhenDucked(false)
                            .build()
                        am.requestAudioFocus(focusReq)
                        activeFocusRequest = focusReq
                    } else {
                        @Suppress("DEPRECATION")
                        am.requestAudioFocus(
                            null,
                            AudioManager.STREAM_MUSIC,
                            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                        )
                    }
                } catch (_: Throwable) {}

                val noisyReceiver = object : BroadcastReceiver() {
                    override fun onReceive(ctx: Context?, intent: Intent?) {
                        if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                            synchronized(audioLock) {
                                releaseActiveHeadphonePlayerLocked()
                            }
                        }
                    }
                }

                try {
                    val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        appCtx.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        appCtx.registerReceiver(noisyReceiver, filter)
                    }
                    activeNoisyReceiver = noisyReceiver
                    activeAudioAppContext = appCtx
                } catch (_: Throwable) {}

                try {
                    val player = MediaPlayer().apply {
                        setAudioAttributes(audioAttrs)
                        setDataSource(appCtx, soundUri)
                        isLooping = false
                        setOnCompletionListener {
                            synchronized(audioLock) {
                                releaseActiveHeadphonePlayerLocked()
                            }
                        }
                        setOnErrorListener { _, _, _ ->
                            synchronized(audioLock) {
                                releaseActiveHeadphonePlayerLocked()
                            }
                            true
                        }
                        prepare()
                    }

                    // Final check right before start() to guarantee zero speaker bleed
                    if (!isHeadphonesConnected(appCtx)) {
                        try {
                            player.release()
                        } catch (_: Throwable) {}
                        releaseActiveHeadphonePlayerLocked()
                        return@synchronized
                    }

                    activeMediaPlayer = player
                    player.start()

                    val stopTask = Runnable {
                        synchronized(audioLock) {
                            releaseActiveHeadphonePlayerLocked()
                        }
                    }
                    activeStopRunnable = stopTask
                    mainHandler.postDelayed(stopTask, maxDurationMs)
                } catch (_: Throwable) {
                    releaseActiveHeadphonePlayerLocked()
                }
            }
        }
    }

    private fun releaseActiveHeadphonePlayerLocked() {
        activeStopRunnable?.let { mainHandler.removeCallbacks(it) }
        activeStopRunnable = null

        activeMediaPlayer?.let { player ->
            try {
                if (player.isPlaying) {
                    player.stop()
                }
            } catch (_: Throwable) {}
            try {
                player.release()
            } catch (_: Throwable) {}
        }
        activeMediaPlayer = null

        val ctx = activeAudioAppContext
        activeNoisyReceiver?.let { receiver ->
            try {
                ctx?.unregisterReceiver(receiver)
            } catch (_: Throwable) {}
        }
        activeNoisyReceiver = null

        if (ctx != null) {
            try {
                val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    activeFocusRequest?.let { am?.abandonAudioFocusRequest(it) }
                } else {
                    @Suppress("DEPRECATION")
                    am?.abandonAudioFocus(null)
                }
            } catch (_: Throwable) {}
        }
        activeFocusRequest = null
        activeAudioAppContext = null
    }

    fun triggerVibration(context: Context, type: String) {
        try {
            val pattern = when (type) {
                "arrival" -> longArrayOf(0, 400, 150, 400, 150, 600)
                "track" -> longArrayOf(0, 250, 120, 350)
                else -> longArrayOf(0, 180, 100, 180)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                val v = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(pattern, -1)
                }
            }
        } catch (_: Throwable) {}
    }
}
