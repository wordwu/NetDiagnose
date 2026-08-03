package com.nettopo.diagnose.ui.screens

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nettopo.diagnose.ui.theme.*
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun ScanScreen(
    progress: String,
    value: Float,
    onCancel: () -> Unit
) {
    // Animated percentage
    val animatedProgress by animateFloatAsState(
        targetValue = value,
        animationSpec = tween(durationMillis = 300)
    )

    // Dot animation
    var dots by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) { delay(300); dots = (dots + 1) % 4 }
    }

    Column(
        modifier = Modifier.fillMaxSize().background(Slate950),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Spacer(modifier = Modifier.weight(1f))

        // ── Circular Progress Ring ────────────────────────────
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(140.dp)) {
            // Background ring
            Canvas(modifier = Modifier.size(140.dp)) {
                val strokeWidth = size.width * 0.06f
                drawArc(
                    color = Cyan500.copy(alpha = 0.1f),
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                )
                // Progress arc
                val sweep = animatedProgress * 360f
                drawArc(
                    brush = Brush.sweepGradient(listOf(Cyan400, Cyan500, Cyan600)),
                    startAngle = -90f,
                    sweepAngle = sweep,
                    useCenter = false,
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                )
            }

            // Percentage text
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "${(animatedProgress * 100).toInt()}%",
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    color = White
                )
                Text("扫描中", fontSize = 11.sp, color = Gray400)
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // ── Progress Text ─────────────────────────────────────
        Text(progress, fontSize = 14.sp, color = Gray400)

        // ── Scanning animation ────────────────────────────────
        Text(
            "📡 正在扫描网络设备${".".repeat(dots)}",
            fontSize = 13.sp,
            color = Cyan400.copy(alpha = 0.7f),
            modifier = Modifier.padding(top = 8.dp)
        )

        Spacer(modifier = Modifier.height(24.dp))

        // ── Cancel Button ─────────────────────────────────────
        TextButton(onClick = onCancel) {
            Text("取消", fontSize = 13.sp, color = Red500.copy(alpha = 0.7f))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}
