package com.my5top.commute

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

class CommuteForegroundService : Service() {

    companion object {
        const val ACTION_START_OR_UPDATE = "com.my5top.commute.action.START_OR_UPDATE"
        const val ACTION_STOP = "com.my5top.commute.action.STOP"
        const val ACTION_USER_STOP = "com.my5top.commute.action.USER_STOP"
        const val ACTION_UI_ATTACHED = "com.my5top.commute.action.UI_ATTACHED"
        const val ACTION_UI_DETACHED = "com.my5top.commute.action.UI_DETACHED"

        const val EXTRA_PAYLOAD_JSON = "payload_json"

        private const val PREFS_NAME = "my5top_bg_guard_prefs"
        private const val KEY_PAYLOAD_JSON = "payload_json"
        private const val KEY_HAS_UPDATES = "bg_has_updates"
        private const val KEY_BG_MODE = "bg_mode"
        private const val KEY_BG_TRAIN_ID = "bg_train_id"
        private const val KEY_BG_STOP_INDEX = "bg_current_stop_index"
        private const val KEY_BG_NOTIFIED_INDICES = "bg_notified_stop_indices"
        private const val KEY_BG_FIRED_WAKEUP = "bg_has_fired_wakeup"
        private const val KEY_BG_SIGNAL_SOURCE = "bg_last_signal_source"
        private const val KEY_BG_DETECTED_TRACK = "bg_detected_track"
        private const val KEY_BG_DETECTED_STATUS = "bg_detected_status"
        private const val KEY_BG_ARRIVED = "bg_arrived"
        private const val KEY_BG_STOPPED_BY_USER = "bg_stopped_by_user"
        private const val KEY_BG_STOP_REASON = "bg_stop_reason"

        private const val NJT_GRAPHQL_URL = "https://www.njtransit.com/api/graphql/graphql"

        // Battery-safe hard cutoffs
        private const val MAX_RIDE_DURATION_MS = 3L * 60L * 60L * 1000L // 3 hours max
        private const val ARRIVAL_STALE_BUFFER_MS = 20L * 60L * 1000L // 20 min past ETA
        private const val POST_ARRIVAL_GRACE_MS = 2L * 60L * 1000L // 2 min after reaching destination
        private const val MAX_WATCH_DURATION_MS = 45L * 60L * 1000L // 45 min max track watch
        private const val WATCH_PAST_DEPARTURE_CAP_MS = 15L * 60L * 1000L // 15 min past scheduled dep
        private const val MAX_FAST_BURST_MS = 8L * 60L * 1000L // 8 min max continuous 1s burst
        private const val RATE_LIMIT_BACKOFF_MS = 30L * 1000L // 30s backoff on HTTP 429/503

        @Volatile
        var isUiAttached: Boolean = true

        @Volatile
        var isRunning: Boolean = false

        fun startOrUpdate(context: Context, payloadJson: String) {
            try {
                val appCtx = context.applicationContext
                appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_PAYLOAD_JSON, payloadJson)
                    .putBoolean(KEY_BG_STOPPED_BY_USER, false)
                    .apply()

                val intent = Intent(appCtx, CommuteForegroundService::class.java).apply {
                    action = ACTION_START_OR_UPDATE
                    putExtra(EXTRA_PAYLOAD_JSON, payloadJson)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appCtx.startForegroundService(intent)
                } else {
                    appCtx.startService(intent)
                }
            } catch (_: Throwable) {}
        }

        fun stopService(context: Context) {
            try {
                val appCtx = context.applicationContext
                appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .remove(KEY_PAYLOAD_JSON)
                    .apply()
                val intent = Intent(appCtx, CommuteForegroundService::class.java).apply {
                    action = ACTION_STOP
                }
                appCtx.startService(intent)
            } catch (_: Throwable) {}
        }

        fun onUiAttached(context: Context) {
            isUiAttached = true
            if (!isRunning) return
            try {
                val appCtx = context.applicationContext
                val intent = Intent(appCtx, CommuteForegroundService::class.java).apply {
                    action = ACTION_UI_ATTACHED
                }
                appCtx.startService(intent)
            } catch (_: Throwable) {}
        }

        fun onUiDetached(context: Context) {
            isUiAttached = false
            if (!isRunning) return
            try {
                val appCtx = context.applicationContext
                val intent = Intent(appCtx, CommuteForegroundService::class.java).apply {
                    action = ACTION_UI_DETACHED
                }
                appCtx.startService(intent)
            } catch (_: Throwable) {}
        }

        fun consumeBackgroundUpdates(context: Context): Map<String, Any?> {
            val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val hasUpdates = prefs.getBoolean(KEY_HAS_UPDATES, false)
            if (!hasUpdates) {
                return mapOf("hasUpdates" to false)
            }
            val notifiedList = mutableListOf<Int>()
            try {
                val rawArr = prefs.getString(KEY_BG_NOTIFIED_INDICES, null)
                if (!rawArr.isNullOrBlank()) {
                    val arr = JSONArray(rawArr)
                    for (i in 0 until arr.length()) {
                        notifiedList.add(arr.optInt(i))
                    }
                }
            } catch (_: Throwable) {}

            val result = mutableMapOf<String, Any?>(
                "hasUpdates" to true,
                "mode" to (prefs.getString(KEY_BG_MODE, "") ?: ""),
                "trainId" to (prefs.getString(KEY_BG_TRAIN_ID, "") ?: ""),
                "currentStopIndex" to prefs.getInt(KEY_BG_STOP_INDEX, -1),
                "notifiedStopIndices" to notifiedList,
                "hasFiredWakeUpAlarm" to prefs.getBoolean(KEY_BG_FIRED_WAKEUP, false),
                "lastTrackingSignalSource" to (prefs.getString(KEY_BG_SIGNAL_SOURCE, "") ?: ""),
                "detectedTrack" to (prefs.getString(KEY_BG_DETECTED_TRACK, "") ?: ""),
                "detectedStatus" to (prefs.getString(KEY_BG_DETECTED_STATUS, "") ?: ""),
                "arrived" to prefs.getBoolean(KEY_BG_ARRIVED, false),
                "stoppedByUser" to prefs.getBoolean(KEY_BG_STOPPED_BY_USER, false),
                "stopReason" to (prefs.getString(KEY_BG_STOP_REASON, "") ?: "")
            )

            prefs.edit()
                .putBoolean(KEY_HAS_UPDATES, false)
                .remove(KEY_BG_DETECTED_TRACK)
                .remove(KEY_BG_STOPPED_BY_USER)
                .remove(KEY_BG_STOP_REASON)
                .apply()

            return result
        }
    }

    private data class BgStop(
        val code: String,
        val name: String,
        val latitude: Double,
        val longitude: Double,
        val estimatedTime: String
    )

    private var executor: ScheduledExecutorService? = null
    private var scheduledTick: ScheduledFuture<*>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var locationManager: LocationManager? = null
    private var gpsListenerRegistered = false

    // Active parsed state
    @Volatile
    private var mode: String = "" // "ride" or "watch"
    private var trainId: String = ""
    private var originCode: String = "NY"
    private var originDvCode: String = "NY"
    private var originShortName: String = "NY Penn"
    private var destCode: String = "MP"
    private var destShortName: String = "Metropark"
    private var departureTime: String = ""
    private var arrivalTime: String = ""
    private var departureEpochMs: Long = 0L
    private var arrivalEpochMs: Long = 0L
    private var startedAtEpochMs: Long = 0L
    private var currentTrack: String = ""
    private var currentStatus: String = "On Time"
    private var currentStopIndex: Int = 0
    private val notifiedStopIndices = mutableSetOf<Int>()
    private var hasFiredWakeUpAlarm: Boolean = false
    private var stops: List<BgStop> = emptyList()

    // Notification rules
    private var notifyEveryStop: Boolean = false
    private var startNotifyingStopsAway: Int = 2
    private var notifyOnTrackAssigned: Boolean = true
    private var finalWakeUpAlarm: Boolean = true
    private var gpsStationRadiusMeters: Double = 550.0
    private var vibrateOnAlerts: Boolean = true
    private var headphoneAudioBypass: Boolean = true
    private var mascotPersonality: String = "mygo"

    // Headless runtime guards
    private var arrivedAtEpochMs: Long = 0L
    private var fastBurstStartedAtMs: Long = 0L
    private var rateLimitBackoffUntilMs: Long = 0L
    private var consecutiveFailures: Int = 0

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            if (!isUiAttached && mode == "ride") {
                handleHeadlessGpsFix(location)
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        CommuteAlertHelper.ensureNotificationChannels(this)
        executor = Executors.newSingleThreadScheduledExecutor()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        when (action) {
            ACTION_STOP -> {
                shutdownService(clearPayload = true)
                return START_NOT_STICKY
            }
            ACTION_USER_STOP -> {
                recordBackgroundDelta(
                    stoppedByUser = true,
                    stopReason = "Stopped from notification"
                )
                shutdownService(clearPayload = true)
                return START_NOT_STICKY
            }
            ACTION_UI_ATTACHED -> {
                isUiAttached = true
                stopNativeGpsUpdates()
                scheduleNextTick(15_000L)
                return START_STICKY
            }
            ACTION_UI_DETACHED -> {
                isUiAttached = false
                if (mode.isEmpty()) {
                    loadPersistedPayloadIfAvailable()
                }
                if (mode.isEmpty()) {
                    shutdownService(clearPayload = true)
                    return START_NOT_STICKY
                }
                if (mode == "ride") {
                    startNativeGpsUpdatesIfPermitted()
                }
                scheduleNextTick(1_000L)
                return START_STICKY
            }
        }

        val rawPayload = intent?.getStringExtra(EXTRA_PAYLOAD_JSON)
            ?: getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_PAYLOAD_JSON, null)

        if (rawPayload.isNullOrBlank() || !parseAndApplyPayload(rawPayload)) {
            shutdownService(clearPayload = true)
            return START_NOT_STICKY
        }

        val notifTitle = extractNotifField(rawPayload, "notificationTitle")
            ?: defaultNotificationTitle()
        val notifBody = extractNotifField(rawPayload, "notificationBody")
            ?: defaultNotificationBody()
        val notifSubText = extractNotifField(rawPayload, "notificationSubText")
            ?: defaultNotificationSubText()

        startForegroundSafely(
            title = notifTitle,
            body = notifBody,
            subText = notifSubText
        )

        if (!isUiAttached && mode == "ride") {
            startNativeGpsUpdatesIfPermitted()
        } else {
            stopNativeGpsUpdates()
        }

        // Schedule next check (fast watchdog if attached, active headless monitor if detached)
        scheduleNextTick(if (isUiAttached) 15_000L else computeHeadlessNextDelayMs())
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // User swiped the app away from Recents! Switch smoothly to native headless mode
        // so commute tracking & track watch survive accidental closing until arrival/cutoff.
        isUiAttached = false
        if (mode.isEmpty()) {
            loadPersistedPayloadIfAvailable()
        }
        if (mode.isNotEmpty()) {
            if (mode == "ride") {
                startNativeGpsUpdatesIfPermitted()
            }
            updateForegroundNotification(
                title = defaultNotificationTitle(),
                body = "${defaultNotificationBody()} • Silent Guard active",
                subText = defaultNotificationSubText()
            )
            scheduleNextTick(1_500L)
        }
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ FGS timeout safeguard: shut down cleanly so OS never crashes the app
        recordBackgroundDelta(stopReason = "System background time limit reached")
        shutdownService(clearPayload = true)
    }

    override fun onDestroy() {
        isRunning = false
        stopNativeGpsUpdates()
        scheduledTick?.cancel(true)
        scheduledTick = null
        try {
            executor?.shutdownNow()
        } catch (_: Throwable) {}
        executor = null
        super.onDestroy()
    }

    private fun extractNotifField(rawJson: String, key: String): String? {
        return try {
            val obj = JSONObject(rawJson)
            val v = obj.optString(key, "").trim()
            if (v.isEmpty()) null else v
        } catch (_: Throwable) {
            null
        }
    }

    private fun loadPersistedPayloadIfAvailable(): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString(KEY_PAYLOAD_JSON, null) ?: return false
        if (!parseAndApplyPayload(saved)) return false
        if (prefs.getString(KEY_BG_TRAIN_ID, "") == trainId) {
            val savedIdx = prefs.getInt(KEY_BG_STOP_INDEX, -1)
            if (savedIdx > currentStopIndex && savedIdx < stops.size) {
                currentStopIndex = savedIdx
            }
            if (prefs.getBoolean(KEY_BG_FIRED_WAKEUP, false)) {
                hasFiredWakeUpAlarm = true
            }
            try {
                val rawNotified = prefs.getString(KEY_BG_NOTIFIED_INDICES, null)
                if (!rawNotified.isNullOrBlank()) {
                    val arr = JSONArray(rawNotified)
                    for (i in 0 until arr.length()) {
                        notifiedStopIndices.add(arr.optInt(i))
                    }
                }
            } catch (_: Throwable) {}
        }
        return true
    }

    private fun parseAndApplyPayload(rawJson: String): Boolean {
        return try {
            val obj = JSONObject(rawJson)
            val parsedMode = obj.optString("mode", "").trim()
            val parsedTrainId = obj.optString("trainId", "").trim()
            if ((parsedMode != "ride" && parsedMode != "watch") || parsedTrainId.isEmpty()) {
                return false
            }

            val trainChanged = parsedMode != mode || parsedTrainId != trainId
            mode = parsedMode
            trainId = parsedTrainId
            originCode = obj.optString("originCode", "NY")
            originDvCode = obj.optString("originDvCode", originCode)
            originShortName = obj.optString("originShortName", "NY Penn")
            destCode = obj.optString("destCode", "MP")
            destShortName = obj.optString("destShortName", "Metropark")
            departureTime = obj.optString("departureTime", "")
            arrivalTime = obj.optString("arrivalTime", "")
            departureEpochMs = obj.optLong("departureEpochMs", 0L)
            arrivalEpochMs = obj.optLong("arrivalEpochMs", 0L)
            val incomingStart = obj.optLong("startedAtEpochMs", 0L)
            startedAtEpochMs = if (incomingStart > 0L) incomingStart else {
                if (startedAtEpochMs > 0L && !trainChanged) startedAtEpochMs else System.currentTimeMillis()
            }
            currentTrack = obj.optString("track", "")
            currentStatus = obj.optString("status", "On Time")

            val incomingStopIdx = obj.optInt("currentStopIndex", 0)
            currentStopIndex = if (trainChanged) incomingStopIdx else maxOf(currentStopIndex, incomingStopIdx)

            if (trainChanged) {
                notifiedStopIndices.clear()
                arrivedAtEpochMs = 0L
                fastBurstStartedAtMs = 0L
                rateLimitBackoffUntilMs = 0L
                consecutiveFailures = 0
            }
            val rawNotified = obj.optJSONArray("notifiedStopIndices")
            if (rawNotified != null) {
                for (i in 0 until rawNotified.length()) {
                    notifiedStopIndices.add(rawNotified.optInt(i))
                }
            }
            hasFiredWakeUpAlarm = if (trainChanged) {
                obj.optBoolean("hasFiredWakeUpAlarm", false)
            } else {
                hasFiredWakeUpAlarm || obj.optBoolean("hasFiredWakeUpAlarm", false)
            }

            val parsedStops = mutableListOf<BgStop>()
            val stopsArr = obj.optJSONArray("stops")
            if (stopsArr != null) {
                for (i in 0 until stopsArr.length()) {
                    val s = stopsArr.optJSONObject(i) ?: continue
                    parsedStops.add(
                        BgStop(
                            code = s.optString("stationCode", ""),
                            name = s.optString("stationName", ""),
                            latitude = s.optDouble("latitude", 0.0),
                            longitude = s.optDouble("longitude", 0.0),
                            estimatedTime = s.optString("estimatedTime", "")
                        )
                    )
                }
            }
            stops = parsedStops

            val rules = obj.optJSONObject("rules")
            if (rules != null) {
                notifyEveryStop = rules.optBoolean("notifyEveryStop", false)
                startNotifyingStopsAway = rules.optInt("startNotifyingStopsAway", 2).coerceIn(1, 10)
                notifyOnTrackAssigned = rules.optBoolean("notifyOnTrackAssigned", true)
                finalWakeUpAlarm = rules.optBoolean("finalWakeUpAlarm", true)
                gpsStationRadiusMeters = rules.optDouble("gpsStationRadiusMeters", 550.0)
                vibrateOnAlerts = rules.optBoolean("vibrateOnAlerts", true)
                headphoneAudioBypass = rules.optBoolean("headphoneAudioBypass", true)
                mascotPersonality = rules.optString("mascotPersonality", "mygo")
            }

            if (mode == "ride" && stopsRemaining() == 0 && arrivedAtEpochMs == 0L) {
                arrivedAtEpochMs = System.currentTimeMillis()
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun stopsRemaining(): Int {
        if (stops.isEmpty()) return 0
        val rem = (stops.size - 1) - currentStopIndex
        return if (rem < 0) 0 else rem
    }

    private fun createStopActionPendingIntent(): PendingIntent {
        val stopIntent = Intent(this, CommuteForegroundService::class.java).apply {
            action = ACTION_USER_STOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getService(this, 5002, stopIntent, flags)
    }

    private fun buildServiceNotification(
        title: String,
        body: String,
        subText: String
    ): Notification {
        val total = if (stops.size > 1) stops.size - 1 else 1
        val passed = currentStopIndex.coerceIn(0, total)
        val stopLabel = if (mode == "watch") "Stop Watch" else "End Ride"
        return CommuteAlertHelper.buildOngoingProgressNotification(
            context = this,
            title = title,
            body = body,
            subText = subText,
            passedStops = passed,
            totalStops = total,
            stopActionLabel = stopLabel,
            stopActionPendingIntent = createStopActionPendingIntent(),
            indeterminate = (mode == "watch")
        )
    }

    private fun startForegroundSafely(title: String, body: String, subText: String) {
        val notif = buildServiceNotification(title, body, subText)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val hasLocPerm = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED ||
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    ) == PackageManager.PERMISSION_GRANTED

                val desiredType = if (mode == "ride" && hasLocPerm) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                }

                try {
                    startForeground(CommuteAlertHelper.NOTIF_ID_LIVE_RIDE, notif, desiredType)
                } catch (_: SecurityException) {
                    // Fallback strictly to DATA_SYNC if background location FGS is restricted
                    startForeground(
                        CommuteAlertHelper.NOTIF_ID_LIVE_RIDE,
                        notif,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                }
            } else {
                startForeground(CommuteAlertHelper.NOTIF_ID_LIVE_RIDE, notif)
            }
        } catch (_: Throwable) {
            try {
                startForeground(CommuteAlertHelper.NOTIF_ID_LIVE_RIDE, notif)
            } catch (_: Throwable) {}
        }
    }

    private fun updateForegroundNotification(title: String, body: String, subText: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(
                CommuteAlertHelper.NOTIF_ID_LIVE_RIDE,
                buildServiceNotification(title, body, subText)
            )
        } catch (_: Throwable) {}
    }

    private fun defaultNotificationTitle(): String {
        if (mode == "watch") {
            return "👀 Watching Track • Train #$trainId ($departureTime)"
        }
        val rem = stopsRemaining()
        return if (rem == 0) {
            "Arrived at $destShortName! • Train #$trainId"
        } else {
            "Train #$trainId → $destShortName ($rem ${if (rem == 1) "stop" else "stops"} away)"
        }
    }

    private fun defaultNotificationBody(): String {
        if (mode == "watch") {
            val statusSuffix = if (currentStatus.isNotBlank()) " • $currentStatus" else ""
            return "Waiting for $originShortName track assignment$statusSuffix"
        }
        val rem = stopsRemaining()
        if (rem == 0) {
            return "Commute complete! Auto-stopping soon to save battery."
        }
        val currName = stops.getOrNull(currentStopIndex)?.name ?: originShortName
        val nextName = stops.getOrNull((currentStopIndex + 1).coerceAtMost(stops.lastIndex.coerceAtLeast(0)))?.name
            ?: destShortName
        return "Passed: $currName • Next: $nextName • ETA $arrivalTime"
    }

    private fun defaultNotificationSubText(): String {
        if (mode == "watch") {
            return if (isInFastTrackBurstWindow(System.currentTimeMillis())) "⚡ 1s Watch" else "Track Watch"
        }
        return if (currentTrack.isNotBlank()) "Track $currentTrack • Guard ON" else "my5top Guard"
    }

    private fun scheduleNextTick(delayMs: Long) {
        scheduledTick?.cancel(false)
        val exec = executor ?: return
        if (exec.isShutdown) return
        scheduledTick = exec.schedule({
            runMonitorTick()
        }, delayMs.coerceAtLeast(500L), TimeUnit.MILLISECONDS)
    }

    private fun runMonitorTick() {
        try {
            val nowMs = System.currentTimeMillis()
            if (checkBatterySafeCutoffs(nowMs)) {
                return
            }

            if (isUiAttached) {
                // UI is alive & driving polling/GPS — stay dormant as a lightweight cutoff watchdog.
                scheduleNextTick(15_000L)
                return
            }

            // Headless mode (UI closed / swiped away): poll NJT API natively!
            if (mode == "ride") {
                pollHeadlessRideStops()
            } else if (mode == "watch") {
                pollHeadlessWatchTrack(nowMs)
            }

            if (isRunning && mode.isNotEmpty()) {
                scheduleNextTick(computeHeadlessNextDelayMs())
            }
        } catch (_: Throwable) {
            if (isRunning && mode.isNotEmpty()) {
                scheduleNextTick(15_000L)
            }
        }
    }

    /**
     * Enforces all battery-drain safeguards and automatic cutoffs.
     * Returns true if the service has shut itself down.
     */
    private fun checkBatterySafeCutoffs(nowMs: Long): Boolean {
        if (mode.isEmpty()) {
            shutdownService(clearPayload = true)
            return true
        }

        if (mode == "ride") {
            // Cutoff 1: Post-arrival grace period expired (2 min after reaching desired stop)
            if (arrivedAtEpochMs > 0L && (nowMs - arrivedAtEpochMs) >= POST_ARRIVAL_GRACE_MS) {
                recordBackgroundDelta(
                    arrived = true,
                    stopReason = "Arrived at $destShortName"
                )
                shutdownService(clearPayload = true)
                return true
            }
            // Cutoff 2: Scheduled arrival overrun cutoff (20 min past ETA)
            if (arrivalEpochMs > 0L && (nowMs - arrivalEpochMs) >= ARRIVAL_STALE_BUFFER_MS) {
                recordBackgroundDelta(
                    arrived = true,
                    stopReason = "Auto-stopped 20m past ETA to save battery"
                )
                shutdownService(clearPayload = true)
                return true
            }
            // Cutoff 3: Hard wall-clock cap (3 hours max)
            if (startedAtEpochMs > 0L && (nowMs - startedAtEpochMs) >= MAX_RIDE_DURATION_MS) {
                recordBackgroundDelta(stopReason = "Auto-stopped after 3h safety cap")
                shutdownService(clearPayload = true)
                return true
            }
        } else if (mode == "watch") {
            if (currentTrack.isNotBlank()) {
                shutdownService(clearPayload = true)
                return true
            }
            if (departureEpochMs > 0L && (nowMs - departureEpochMs) >= WATCH_PAST_DEPARTURE_CAP_MS) {
                recordBackgroundDelta(stopReason = "Train departure window passed")
                shutdownService(clearPayload = true)
                return true
            }
            if (startedAtEpochMs > 0L && (nowMs - startedAtEpochMs) >= MAX_WATCH_DURATION_MS) {
                recordBackgroundDelta(stopReason = "Auto-stopped after 45m track watch cap")
                shutdownService(clearPayload = true)
                return true
            }
        }

        return false
    }

    private fun isNonRoutineCondition(status: String): Boolean {
        val s = status.trim().lowercase()
        if (s.isEmpty() || s == "on time" || s == "ontime" || s == "scheduled" || s == "track tba") {
            return false
        }
        if (Regex("^in\\s+\\d+\\s*min").containsMatchIn(s)) {
            return false
        }
        if (s.contains("cancel")) return false
        return true
    }

    private fun isInFastTrackBurstWindow(nowMs: Long): Boolean {
        if (mode != "watch" || currentTrack.isNotBlank() || departureEpochMs <= 0L) return false
        if (nowMs < rateLimitBackoffUntilMs) return false
        val secsUntilDep = (departureEpochMs - nowMs) / 1000L

        // Standard 11-min to 9-min guardrail window (660s .. 540s)
        if (secsUntilDep in 540L..660L) {
            if (fastBurstStartedAtMs == 0L) fastBurstStartedAtMs = nowMs
            return true
        }

        // Exception: Delayed or non-routine condition extends fast polling past 9m mark
        // (capped at 8 minutes total continuous burst for battery/API safety)
        if (isNonRoutineCondition(currentStatus) && secsUntilDep in -900L..660L) {
            if (fastBurstStartedAtMs == 0L) fastBurstStartedAtMs = nowMs
            return (nowMs - fastBurstStartedAtMs) <= MAX_FAST_BURST_MS
        }

        return false
    }

    private fun computeHeadlessNextDelayMs(): Long {
        val nowMs = System.currentTimeMillis()
        if (mode == "watch") {
            if (isInFastTrackBurstWindow(nowMs)) {
                return 1_000L
            }
            if (consecutiveFailures >= 5) return 30_000L
            val secsUntilDep = if (departureEpochMs > 0L) (departureEpochMs - nowMs) / 1000L else 0L
            return if (secsUntilDep > 1200L) 15_000L else 5_000L
        }
        // Ride mode: battery-friendly 15s API polling (backs off to 60s if network offline)
        return if (consecutiveFailures >= 8) 60_000L else 15_000L
    }

    private fun pollHeadlessWatchTrack(nowMs: Long) {
        val query = """query { board: getTrainDepartureScreens(station: "$originDvCode") { items { trainID status track inlineMessage } } }"""
        val (statusCode, body) = executeGraphQl(query, 4000)
        if (statusCode == 429 || statusCode == 503) {
            rateLimitBackoffUntilMs = nowMs + RATE_LIMIT_BACKOFF_MS
            consecutiveFailures++
            return
        }
        if (statusCode != 200 || body == null) {
            consecutiveFailures++
            return
        }
        consecutiveFailures = 0

        try {
            val root = JSONObject(body)
            val items = root.optJSONObject("data")
                ?.optJSONObject("board")
                ?.optJSONArray("items") ?: return

            for (i in 0 until items.length()) {
                val item = items.optJSONObject(i) ?: continue
                val id = item.optString("trainID", "").trim()
                if (id != trainId) continue

                val track = item.optString("track", "").trim()
                val rawStatus = item.optString("status", "").trim()
                val inlineMsg = item.optString("inlineMessage", "").trim()
                val normalizedStatus = normalizeStatus(rawStatus, inlineMsg)
                currentStatus = normalizedStatus

                if (normalizedStatus.contains("Cancel", ignoreCase = true)) {
                    CommuteAlertHelper.showCommuteAlertNotification(
                        context = this,
                        id = (System.currentTimeMillis() % 100000).toInt(),
                        type = "track",
                        title = "⚠️ Train #$trainId Cancelled",
                        body = "DepartureVision marked Train #$trainId as Cancelled at $originShortName.",
                        vibrate = vibrateOnAlerts,
                        headphoneAudioBypass = headphoneAudioBypass
                    )
                    recordBackgroundDelta(
                        detectedStatus = normalizedStatus,
                        stopReason = "Train cancelled"
                    )
                    shutdownService(clearPayload = true)
                    return
                }

                if (normalizedStatus.contains("Depart", ignoreCase = true)) {
                    CommuteAlertHelper.showCommuteAlertNotification(
                        context = this,
                        id = (System.currentTimeMillis() % 100000).toInt(),
                        type = "info",
                        title = "🚉 Train #$trainId Departed $originShortName",
                        body = "Track watch stopped automatically since Train #$trainId departed.",
                        vibrate = false,
                        headphoneAudioBypass = false
                    )
                    recordBackgroundDelta(
                        detectedStatus = normalizedStatus,
                        stopReason = "Train departed"
                    )
                    shutdownService(clearPayload = true)
                    return
                }

                if (track.isNotEmpty()) {
                    currentTrack = track
                    if (notifyOnTrackAssigned) {
                        val isSakura = mascotPersonality == "sakura"
                        val title = "⚡ TRACK $track POSTED! • Train #$trainId"
                        val alertBody = if (isSakura) {
                            "★ Hana-chan: Train #$trainId to $destShortName is boarding on Track $track ($departureTime)! Hurry to the stairs~ ♪"
                        } else {
                            "✦ Tomori-navi: Track $track announced at $originShortName for Train #$trainId → $destShortName ($departureTime). Move now!"
                        }
                        CommuteAlertHelper.showCommuteAlertNotification(
                            context = this,
                            id = (System.currentTimeMillis() % 100000).toInt(),
                            type = "track",
                            title = title,
                            body = alertBody,
                            vibrate = vibrateOnAlerts,
                            headphoneAudioBypass = headphoneAudioBypass
                        )
                    }
                    recordBackgroundDelta(
                        detectedTrack = track,
                        detectedStatus = normalizedStatus,
                        stopReason = "Track $track announced"
                    )
                    shutdownService(clearPayload = true)
                    return
                }

                updateForegroundNotification(
                    title = defaultNotificationTitle(),
                    body = defaultNotificationBody(),
                    subText = defaultNotificationSubText()
                )
                return
            }
        } catch (_: Throwable) {}
    }

    private fun pollHeadlessRideStops() {
        val query = """query { stops: getTrainStopList(train: "$trainId") { name time departed status } }"""
        val (statusCode, body) = executeGraphQl(query, 6000)
        if (statusCode != 200 || body == null) {
            consecutiveFailures++
            return
        }
        consecutiveFailures = 0

        try {
            val root = JSONObject(body)
            val apiStops = root.optJSONObject("data")?.optJSONArray("stops") ?: return
            if (apiStops.length() == 0 || stops.isEmpty()) return

            var highestDepartedIdx = currentStopIndex
            for (i in 0 until apiStops.length()) {
                val s = apiStops.optJSONObject(i) ?: continue
                if (!s.optBoolean("departed", false)) continue
                val rawName = normalizeKey(s.optString("name", ""))
                if (rawName.isEmpty()) continue
                val apiCode = resolveStationCode(rawName)

                for (localIdx in (highestDepartedIdx + 1) until stops.size) {
                    val localStop = stops[localIdx]
                    val localName = normalizeKey(localStop.name)
                    val codeMatch = apiCode != null && apiCode.equals(localStop.code, ignoreCase = true)
                    val exactNameMatch = rawName == localName
                    if (codeMatch || exactNameMatch) {
                        highestDepartedIdx = localIdx
                        break
                    }
                }
            }

            if (highestDepartedIdx > currentStopIndex) {
                advanceHeadlessStop(highestDepartedIdx, "Silent API Guard")
            }
        } catch (_: Throwable) {}
    }

    private fun resolveStationCode(normalizedName: String): String? {
        return when {
            normalizedName.contains("new york") || normalizedName.contains("ny penn") -> "NY"
            normalizedName.contains("secaucus") -> "SE"
            normalizedName.contains("newark penn") -> "NP"
            normalizedName.contains("airport") || normalizedName.contains("ewr") -> "NA"
            normalizedName.contains("north elizabeth") || normalizedName.contains("n elizabeth") -> "NE"
            normalizedName == "elizabeth" || normalizedName.startsWith("elizabeth ") -> "EZ"
            normalizedName.contains("linden") -> "LI"
            normalizedName.contains("rahway") -> "RA"
            normalizedName.contains("metropark") -> "MP"
            normalizedName.contains("metuchen") -> "MC"
            normalizedName.contains("edison") -> "ED"
            normalizedName.contains("new brunswick") -> "NB"
            normalizedName.contains("jersey ave") -> "JA"
            normalizedName.contains("princeton") -> "PJ"
            normalizedName.contains("hamilton") -> "HL"
            normalizedName.contains("trenton") -> "TR"
            normalizedName.contains("hoboken") -> "HB"
            else -> null
        }
    }

    private fun startNativeGpsUpdatesIfPermitted() {
        if (gpsListenerRegistered) return
        val hasFine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) return

        mainHandler.post {
            if (gpsListenerRegistered || isUiAttached || mode != "ride") return@post
            try {
                val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return@post
                locationManager = lm
                if (hasFine && lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        20_000L,
                        100f,
                        locationListener,
                        Looper.getMainLooper()
                    )
                    gpsListenerRegistered = true
                }
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        25_000L,
                        150f,
                        locationListener,
                        Looper.getMainLooper()
                    )
                    gpsListenerRegistered = true
                }
            } catch (_: Throwable) {}
        }
    }

    private fun stopNativeGpsUpdates() {
        mainHandler.post {
            if (!gpsListenerRegistered) return@post
            try {
                locationManager?.removeUpdates(locationListener)
            } catch (_: Throwable) {}
            gpsListenerRegistered = false
        }
    }

    private fun handleHeadlessGpsFix(loc: Location) {
        if (stops.isEmpty()) return
        for (i in (currentStopIndex + 1) until stops.size) {
            val st = stops[i]
            val dist = haversineMeters(loc.latitude, loc.longitude, st.latitude, st.longitude)
            if (dist <= gpsStationRadiusMeters) {
                advanceHeadlessStop(i, "Silent GPS Geofence (${dist.toInt()}m)")
                break
            }
        }

        val destStop = stops.last()
        val distToDest = haversineMeters(loc.latitude, loc.longitude, destStop.latitude, destStop.longitude)
        if (finalWakeUpAlarm &&
            !hasFiredWakeUpAlarm &&
            distToDest <= 950.0 &&
            stopsRemaining() <= 1
        ) {
            hasFiredWakeUpAlarm = true
            fireHeadlessArrivalAlarm("Within ${distToDest.toInt()}m of $destShortName")
            recordBackgroundDelta(lastSignalSource = "Silent GPS Geofence")
        }
    }

    private fun advanceHeadlessStop(newIndex: Int, source: String) {
        if (stops.isEmpty()) return
        val clamped = newIndex.coerceIn(0, stops.lastIndex)
        if (clamped <= currentStopIndex) return

        currentStopIndex = clamped
        val rem = stopsRemaining()
        val currentStop = stops[clamped]
        val isSakura = mascotPersonality == "sakura"

        if (rem == 0 && arrivedAtEpochMs == 0L) {
            arrivedAtEpochMs = System.currentTimeMillis()
            stopNativeGpsUpdates()
        }

        updateForegroundNotification(
            title = defaultNotificationTitle(),
            body = defaultNotificationBody(),
            subText = defaultNotificationSubText()
        )

        if (!notifiedStopIndices.contains(clamped)) {
            notifiedStopIndices.add(clamped)
            if (rem == 0) {
                if (!hasFiredWakeUpAlarm) {
                    hasFiredWakeUpAlarm = true
                    fireHeadlessArrivalAlarm("Arrived at $destShortName!")
                }
            } else if (rem <= startNotifyingStopsAway) {
                val isOneStopAway = rem == 1
                val title = if (isOneStopAway) {
                    "🚨 1 STOP AWAY! Next: $destShortName"
                } else {
                    "🔔 $rem Stops Away from $destShortName!"
                }
                val body = if (isOneStopAway) {
                    if (isSakura) {
                        "★ Passing ${currentStop.name}! $destShortName is NEXT (ETA $arrivalTime)! Pack up & head to the doors~ ♪"
                    } else {
                        "⚡ Passed ${currentStop.name}. $destShortName is the NEXT stop (ETA $arrivalTime). Time to stand up!"
                    }
                } else {
                    if (isSakura) {
                        "✿ Now at ${currentStop.name} • Only $rem stops left until $destShortName (ETA $arrivalTime)~!"
                    } else {
                        "✦ Cleared ${currentStop.name} ($source). $rem stops left to $destShortName • ETA $arrivalTime."
                    }
                }
                CommuteAlertHelper.showCommuteAlertNotification(
                    context = this,
                    id = (System.currentTimeMillis() % 100000).toInt(),
                    type = if (isOneStopAway) "arrival" else "stop",
                    title = title,
                    body = body,
                    vibrate = vibrateOnAlerts,
                    headphoneAudioBypass = headphoneAudioBypass
                )
            } else if (notifyEveryStop) {
                val nextName = stops.getOrNull(clamped + 1)?.name ?: destShortName
                CommuteAlertHelper.showCommuteAlertNotification(
                    context = this,
                    id = (System.currentTimeMillis() % 100000).toInt(),
                    type = "stop",
                    title = "🚉 Passed ${currentStop.name} ($rem stops left)",
                    body = "Next stop: $nextName • Destination ETA: $arrivalTime",
                    vibrate = vibrateOnAlerts,
                    headphoneAudioBypass = headphoneAudioBypass
                )
            }
        }

        recordBackgroundDelta(
            lastSignalSource = source,
            arrived = (rem == 0)
        )
    }

    private fun fireHeadlessArrivalAlarm(reason: String) {
        val isSakura = mascotPersonality == "sakura"
        val body = if (isSakura) {
            "★ $reason! Check your seat for your phone, headphones & bag before stepping off~ ♪"
        } else {
            "⚡ $reason! Grab your bag and step onto the platform safely."
        }
        CommuteAlertHelper.showCommuteAlertNotification(
            context = this,
            id = (System.currentTimeMillis() % 100000).toInt(),
            type = "arrival",
            title = "🎉 ARRIVING AT ${destShortName.uppercase()}!",
            body = body,
            vibrate = true,
            headphoneAudioBypass = headphoneAudioBypass
        )
    }

    private fun recordBackgroundDelta(
        lastSignalSource: String? = null,
        detectedTrack: String? = null,
        detectedStatus: String? = null,
        arrived: Boolean = false,
        stoppedByUser: Boolean = false,
        stopReason: String? = null
    ) {
        try {
            val notifiedArr = JSONArray()
            for (idx in notifiedStopIndices) {
                notifiedArr.put(idx)
            }
            val editor = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_HAS_UPDATES, true)
                .putString(KEY_BG_MODE, mode)
                .putString(KEY_BG_TRAIN_ID, trainId)
                .putInt(KEY_BG_STOP_INDEX, currentStopIndex)
                .putString(KEY_BG_NOTIFIED_INDICES, notifiedArr.toString())
                .putBoolean(KEY_BG_FIRED_WAKEUP, hasFiredWakeUpAlarm)
                .putBoolean(KEY_BG_ARRIVED, arrived)
            if (lastSignalSource != null) editor.putString(KEY_BG_SIGNAL_SOURCE, lastSignalSource)
            if (detectedTrack != null) editor.putString(KEY_BG_DETECTED_TRACK, detectedTrack)
            if (detectedStatus != null) editor.putString(KEY_BG_DETECTED_STATUS, detectedStatus)
            if (stoppedByUser) editor.putBoolean(KEY_BG_STOPPED_BY_USER, true)
            if (stopReason != null) editor.putString(KEY_BG_STOP_REASON, stopReason)
            editor.apply()
        } catch (_: Throwable) {}
    }

    private fun shutdownService(clearPayload: Boolean) {
        stopNativeGpsUpdates()
        scheduledTick?.cancel(false)
        scheduledTick = null
        mode = ""
        isRunning = false
        if (clearPayload) {
            try {
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .remove(KEY_PAYLOAD_JSON)
                    .apply()
            } catch (_: Throwable) {}
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
        CommuteAlertHelper.cancelRideProgressNotification(this)
        stopSelf()
    }

    private fun executeGraphQl(query: String, timeoutMs: Int): Pair<Int, String?> {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(NJT_GRAPHQL_URL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
            }
            val payload = JSONObject().put("query", query).toString()
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(payload)
                writer.flush()
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.let {
                BufferedReader(InputStreamReader(it, Charsets.UTF_8)).use { br -> br.readText() }
            }
            Pair(code, text)
        } catch (_: Throwable) {
            Pair(-1, null)
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Throwable) {}
        }
    }

    private fun normalizeStatus(rawStatus: String, inlineMsg: String): String {
        val s = rawStatus.trim()
        if (s.isEmpty()) {
            return if (inlineMsg.contains("delay", ignoreCase = true)) "Delayed" else "On Time"
        }
        return when (s.uppercase()) {
            "ONTIME", "ON TIME" -> "On Time"
            "BOARDING" -> "Boarding"
            "ALL ABOARD" -> "All Aboard"
            "STAND BY" -> "Stand By"
            "CANCELLED", "CANCELED" -> "Cancelled"
            "DELAYED" -> "Delayed"
            "DEPARTED" -> "Departed"
            else -> s
        }
    }

    private fun normalizeKey(raw: String): String {
        return raw.lowercase()
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadius = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}
