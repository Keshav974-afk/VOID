package com.psyche.kelivo.background

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.PixelFormat
import android.graphics.SweepGradient
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.Chronometer
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/** Compact circular floating overlay ("OP UI"):
 * - 68x68 dp circle footprint (never covers the whole screen)
 * - Stopwatch Chronometer counting elapsed execution time
 * - Animated Gemini-style revolving orbital ring
 * - Active Phone Control indicator badge when automating the device
 * - Draggable anywhere with touch, tap to open app/conversation.
 */
class BackgroundOverlay(
    private val context: Context,
    private val runtime: BackgroundRuntime,
    private val prefs: SharedPreferences,
) {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var view: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var indicatorView: OverlayIconView? = null
    private var clock: Chronometer? = null
    private var spinner: OverlayProgressRing? = null
    private var current: BackgroundTask? = null
    private var completed: BackgroundTask? = null
    private val dismissed = mutableSetOf<String>()
    private val expire = Runnable { completed = null; refresh() }
    private var pendingLongPress: Runnable? = null
    val isVisible get() = view != null

    fun sync(tasks: List<BackgroundTask>, terminal: BackgroundTask?) {
        if (terminal != null) {
            if (terminal.outcome == "cancelled") {
                if (completed?.id == terminal.id) completed = null
            } else if (tasks.isEmpty() && !runtime.foreground && runtime.enabled("overlayEnabled") &&
                terminal.id !in dismissed && current?.id == terminal.id && isVisible) {
                completed = terminal
            }
        }
        if (tasks.isNotEmpty()) completed = null
        if (!runtime.enabled("overlayEnabled") && !runtime.phoneControlActive) completed = null
        dismissed.retainAll(tasks.map { it.id }.toSet() + listOfNotNull(completed?.id))
        refresh()
    }

    fun onForegroundChanged(foreground: Boolean) {
        if (foreground) completed = null
        refresh()
    }

    fun dismissAll() {
        dismissed.addAll(runtime.tasks.map { it.id })
        completed = null
        hide()
    }

    fun clearCompleted() { completed = null }

    fun refresh() {
        main.removeCallbacks(expire)
        val isPhoneControl = runtime.phoneControlActive
        if (runtime.foreground || (!runtime.enabled("overlayEnabled") && !isPhoneControl) ||
            !Settings.canDrawOverlays(context) || runtime.isPromoted()) {
            hide()
            return
        }

        val seconds = ((runtime.setting("completionSeconds") as? Number)?.toLong() ?: 60).coerceIn(0, 900)
        val finish = completed
        if (finish != null) {
            val remaining = finish.finishedAt + seconds * 1000 - System.currentTimeMillis()
            if (remaining <= 0) completed = null else main.postDelayed(expire, remaining)
        }

        val task = runtime.tasks.firstOrNull { it.id !in dismissed }
            ?: completed
            ?: if (isPhoneControl) {
                val start = if (runtime.phoneControlStartedAt > 0) runtime.phoneControlStartedAt else System.currentTimeMillis()
                BackgroundTask(
                    id = "phone_control",
                    conversationId = "",
                    title = "Phone Control",
                    detail = "Controlling phone",
                    startedAt = start,
                    tokens = 0
                )
            } else null

        if (task == null) {
            hide()
            return
        }
        current = task

        try {
            if (view == null) create()

            // Update Phone Control / Voice / Status indicator
            val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            indicatorView?.apply {
                isDark = dark
                mode = when {
                    isPhoneControl -> OverlayIconMode.PHONE_CONTROL
                    task.outcome == "completed" -> OverlayIconMode.COMPLETED
                    task.outcome.isNotEmpty() -> OverlayIconMode.FAILED
                    else -> OverlayIconMode.AI_THINKING
                }
            }

            // Update Stopwatch Chronometer
            clock?.apply {
                stop()
                if (task.outcome.isEmpty()) {
                    base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - task.startedAt).coerceAtLeast(0)
                    start()
                } else {
                    val duration = ((task.finishedAt - task.startedAt) / 1000).coerceAtLeast(0)
                    text = "%d:%02d".format(duration / 60, duration % 60)
                }
            }

            spinner?.invalidate()
            clampPosition()
        } catch (error: RuntimeException) {
            runtime.recordError("overlay_failed: ${error.message}")
            hide()
        }
    }

    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
    private fun dp(value: Float) = (value * context.resources.displayMetrics.density).toInt()

    private fun create() {
        val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val isPhoneControl = runtime.phoneControlActive

        // Root 68x68 dp circular floating bubble - sleek frosted glass & micro hairline bevel
        val root = FrameLayout(context).apply {
            tag = "overlay"
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(if (dark) Color.argb(248, 16, 18, 22) else Color.argb(248, 248, 250, 252))
                val strokeColor = if (isPhoneControl) Color.argb(90, 52, 211, 153) else if (dark) Color.argb(32, 255, 255, 255) else Color.argb(22, 0, 0, 0)
                setStroke(dp(1.0f), strokeColor)
            }
            background = bg
            elevation = dp(8).toFloat()
            setOnLongClickListener { dismissAll(); true }
        }

        // 1. Revolving Ring: Orbiting around circle perimeter with subtle comet falloff
        val ring = OverlayProgressRing(context, dp(2.2f).coerceAtLeast(2).toFloat()) {
            runtime.phoneControlActive
        }
        spinner = ring
        root.addView(ring, FrameLayout.LayoutParams(dp(68), dp(68), Gravity.CENTER))

        // 2. Centered Content: Minimalist Vector Icon + Stopwatch
        val contentColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }

        val iconView = OverlayIconView(context).apply {
            this.isDark = dark
            this.mode = if (isPhoneControl) OverlayIconMode.PHONE_CONTROL else OverlayIconMode.AI_THINKING
        }
        indicatorView = iconView
        contentColumn.addView(
            iconView,
            LinearLayout.LayoutParams(dp(16), dp(16)).apply {
                bottomMargin = dp(2)
            }
        )

        clock = Chronometer(context).apply {
            tag = "time"
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextColor(if (dark) Color.parseColor("#E2E8F0") else Color.parseColor("#1E293B"))
            setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL))
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, 10.5f)
        }
        contentColumn.addView(
            clock,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        )

        root.addView(contentColumn, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        // Layout params: 68x68 dp
        val metrics = context.resources.displayMetrics
        val layout = WindowManager.LayoutParams(
            dp(68), dp(68),
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = prefs.getInt("overlay_x", dp(16))
            y = prefs.getInt("overlay_y", metrics.heightPixels / 2)
        }
        params = layout

        var startX = 0; var startY = 0
        var touchX = 0f; var touchY = 0f; var dragging = false; var longPressed = false
        val longPress = Runnable { longPressed = true; root.performLongClick() }
        pendingLongPress = longPress

        root.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = layout.x; startY = layout.y
                    touchX = event.rawX; touchY = event.rawY; dragging = false
                    longPressed = false
                    main.postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong())
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX; val dy = event.rawY - touchY
                    if (abs(dx) + abs(dy) > dp(6)) { dragging = true; main.removeCallbacks(longPress) }
                    if (dragging) {
                        layout.x = startX + dx.toInt(); layout.y = startY + dy.toInt()
                        clampPosition()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    main.removeCallbacks(longPress)
                    if (dragging) {
                        prefs.edit().putInt("overlay_x", layout.x).putInt("overlay_y", layout.y).apply()
                    } else if (!longPressed) {
                        current?.let { task ->
                            completed = null
                            if (task.conversationId.isNotEmpty()) {
                                hide()
                                runtime.openConversation(task.conversationId)
                            } else {
                                // Bring Kelivo MainActivity to front
                                val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                                }
                                if (intent != null) context.startActivity(intent)
                            }
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> { main.removeCallbacks(longPress); true }
                else -> false
            }
        }

        windowManager.addView(root, layout)
        view = root
    }

    private fun clampPosition() {
        val layout = params ?: return
        val root = view ?: return
        val metrics = context.resources.displayMetrics
        layout.x = layout.x.coerceIn(0, (metrics.widthPixels - layout.width).coerceAtLeast(0))
        layout.y = layout.y.coerceIn(dp(24), (metrics.heightPixels - layout.height).coerceAtLeast(dp(24)))
        try { windowManager.updateViewLayout(root, layout) } catch (_: IllegalArgumentException) { hide() }
    }

    private fun hide() {
        pendingLongPress?.let(main::removeCallbacks)
        pendingLongPress = null
        clock?.stop()
        view?.let { try { windowManager.removeView(it) } catch (_: IllegalArgumentException) {} }
        view = null; params = null; indicatorView = null; clock = null; spinner = null
    }
}

private enum class OverlayIconMode {
    AI_THINKING,
    PHONE_CONTROL,
    COMPLETED,
    FAILED,
}

/** Clean, minimal vector glyphs for overlay indicator (zero childish emojis). */
private class OverlayIconView(context: Context) : View(context) {
    var mode: OverlayIconMode = OverlayIconMode.AI_THINKING
        set(value) {
            if (field != value) {
                field = value
                invalidate()
            }
        }

    var isDark: Boolean = true
        set(value) {
            if (field != value) {
                field = value
                invalidate()
            }
        }

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val path = Path()

    private fun dp(v: Float) = v * resources.displayMetrics.density

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        val cx = w / 2f
        val cy = h / 2f

        val primaryColor = if (isDark) Color.parseColor("#E2E8F0") else Color.parseColor("#1E293B")
        val accentMint = Color.parseColor("#34D399")
        val errorRose = Color.parseColor("#F87171")

        when (mode) {
            OverlayIconMode.PHONE_CONTROL -> {
                // Sleek minimalist smartphone vector
                val phoneW = dp(9.5f)
                val phoneH = dp(14f)
                val radius = dp(2f)
                val left = cx - phoneW / 2f
                val top = cy - phoneH / 2f
                val right = cx + phoneW / 2f
                val bottom = cy + phoneH / 2f

                strokePaint.color = accentMint
                strokePaint.strokeWidth = dp(1.2f)
                val rect = RectF(left, top, right, bottom)
                canvas.drawRoundRect(rect, radius, radius, strokePaint)

                // Minimal home bar
                val barW = dp(3.8f)
                strokePaint.strokeWidth = dp(1.0f)
                canvas.drawLine(cx - barW / 2f, bottom - dp(2.2f), cx + barW / 2f, bottom - dp(2.2f), strokePaint)
            }
            OverlayIconMode.AI_THINKING -> {
                // Sleek 4-point concave diamond star (Apple Intelligence / Modern AI mark)
                val size = dp(12f)
                val half = size / 2f
                val indent = size * 0.16f

                path.reset()
                path.moveTo(cx, cy - half)
                path.quadTo(cx + indent, cy - indent, cx + half, cy)
                path.quadTo(cx + indent, cy + indent, cx, cy + half)
                path.quadTo(cx - indent, cy + indent, cx - half, cy)
                path.quadTo(cx - indent, cy - indent, cx, cy - half)
                path.close()

                fillPaint.color = primaryColor
                canvas.drawPath(path, fillPaint)
            }
            OverlayIconMode.COMPLETED -> {
                // Crisp minimal checkmark
                strokePaint.color = accentMint
                strokePaint.strokeWidth = dp(1.4f)
                path.reset()
                path.moveTo(cx - dp(4f), cy)
                path.lineTo(cx - dp(1f), cy + dp(3.2f))
                path.lineTo(cx + dp(4.5f), cy - dp(3.2f))
                canvas.drawPath(path, strokePaint)
            }
            OverlayIconMode.FAILED -> {
                // Crisp minimal cross
                strokePaint.color = errorRose
                strokePaint.strokeWidth = dp(1.3f)
                val d = dp(3.2f)
                canvas.drawLine(cx - d, cy - d, cx + d, cy + d, strokePaint)
                canvas.drawLine(cx + d, cy - d, cx - d, cy + d, strokePaint)
            }
        }
    }
}

/** Precision revolving orbital ring with sophisticated comet falloff. */
private class OverlayProgressRing(
    context: Context,
    private val stroke: Float,
    private val isPhoneControl: () -> Boolean,
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
    }
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke * 0.75f
    }
    private var animator: ObjectAnimator? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateShader(w, h)
    }

    private fun updateShader(w: Int = width, h: Int = height) {
        if (w <= 0 || h <= 0) return
        val cx = w / 2f
        val cy = h / 2f
        val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val isPc = isPhoneControl()

        val colors = if (isPc) {
            // Refined cyber mint / sage comet trail
            intArrayOf(
                Color.argb(0, 52, 211, 153),
                Color.argb(35, 52, 211, 153),
                Color.argb(125, 16, 185, 129),
                Color.argb(240, 52, 211, 153)
            )
        } else {
            // Sophisticated titanium / slate comet trail
            if (dark) {
                intArrayOf(
                    Color.argb(0, 147, 197, 253),
                    Color.argb(35, 147, 197, 253),
                    Color.argb(110, 99, 102, 241),
                    Color.argb(235, 226, 232, 240)
                )
            } else {
                intArrayOf(
                    Color.argb(0, 99, 102, 241),
                    Color.argb(25, 99, 102, 241),
                    Color.argb(90, 79, 70, 229),
                    Color.argb(230, 30, 41, 59)
                )
            }
        }
        val sweep = SweepGradient(cx, cy, colors, floatArrayOf(0f, 0.35f, 0.75f, 1f))
        paint.shader = sweep
    }

    override fun onDraw(canvas: Canvas) {
        val inset = stroke / 2f + 1f
        val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        // Faint precision bezel track
        trackPaint.color = if (dark) Color.argb(18, 255, 255, 255) else Color.argb(15, 0, 0, 0)
        canvas.drawCircle(width / 2f, height / 2f, width / 2f - inset, trackPaint)

        updateShader()
        // 270 degree smooth comet arc
        canvas.drawArc(inset, inset, width - inset, height - inset, 0f, 270f, false, paint)
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); updateAnimation() }
    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility); updateAnimation()
    }
    override fun onDetachedFromWindow() { animator?.cancel(); animator = null; super.onDetachedFromWindow() }

    private fun updateAnimation() {
        if (!isAttachedToWindow || visibility != VISIBLE) {
            animator?.cancel(); animator = null; return
        }
        if (animator != null) return
        animator = ObjectAnimator.ofFloat(this, ROTATION, 0f, 360f).apply {
            duration = 1350
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            start()
        }
    }
}
