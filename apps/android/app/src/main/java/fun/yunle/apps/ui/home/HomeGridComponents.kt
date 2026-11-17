package `fun`.yunle.apps.ui.home

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.home.HomeFolder
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import kotlin.math.abs

internal data class HomeGridMetrics(
    val width: Dp,
    val columns: Int,
    val gap: Dp,
    val cellWidth: Dp,
) {
    val labelWidth: Dp = cellWidth

    companion object {
        val MARGIN = 16.dp
        val ICON_SIZE = 60.dp
        val COLUMN_SPACING = 8.dp
        val ROW_SPACING = 18.dp

        fun calculate(availableWidth: Dp): HomeGridMetrics {
            val safeWidth = availableWidth.coerceAtLeast(ICON_SIZE * 4 + COLUMN_SPACING * 3)
            val columns = if (safeWidth >= 560.dp) {
                maxOf(4, ((safeWidth.value + 24f) / (ICON_SIZE.value + 24f)).toInt())
            } else {
                4
            }
            val cellWidth = ((safeWidth - COLUMN_SPACING * (columns - 1)) / columns)
                .coerceAtLeast(ICON_SIZE)
            val gap = ((safeWidth - ICON_SIZE * columns) / (columns - 1)).coerceAtLeast(COLUMN_SPACING)
            return HomeGridMetrics(
                width = safeWidth,
                columns = columns,
                gap = gap,
                cellWidth = cellWidth,
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun HomeAppGlyph(
    name: String,
    showsName: Boolean = true,
    labelWidth: Dp = HomeGridMetrics.ICON_SIZE,
    isUnavailable: Boolean = false,
    wobbling: Boolean = false,
    seedKey: String = name,
    isSelected: Boolean = false,
    isMergeTarget: Boolean = false,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    onRemoveClick: (() -> Unit)? = null,
    removeContentDescription: String = "移出 $name",
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
) {
    val rotationAngle = if (wobbling) {
        val transition = rememberInfiniteTransition(label = "wobble_$seedKey")
        val phaseOffset = (abs(seedKey.hashCode()) % 120)
        val angle by transition.animateFloat(
            initialValue = -1.6f,
            targetValue = 1.6f,
            animationSpec = infiniteRepeatable(
                animation = tween(
                    durationMillis = 150 + (phaseOffset % 40),
                    delayMillis = phaseOffset / 3,
                    easing = FastOutSlowInEasing,
                ),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "angle",
        )
        angle
    } else {
        0f
    }

    val targetScale by animateFloatAsState(
        targetValue = if (isMergeTarget) 1.08f else 1f,
        label = "mergeScale",
    )

    val clickableModifier = if (onClick != null || onLongClick != null) {
        Modifier.combinedClickable(
            onClick = { onClick?.invoke() },
            onLongClick = onLongClick,
        )
    } else {
        Modifier
    }

    Column(
        modifier = modifier
            .then(if (labelWidth != Dp.Unspecified) Modifier.width(labelWidth) else Modifier.fillMaxWidth())
            .then(clickableModifier),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .size(HomeGridMetrics.ICON_SIZE)
                .graphicsLayer {
                    rotationZ = rotationAngle
                    scaleX = targetScale
                    scaleY = targetScale
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(HomeGridMetrics.ICON_SIZE)
                    .clip(RoundedCornerShape(16.dp))
                    .then(
                        if (isMergeTarget) {
                            Modifier.border(
                                width = 2.5.dp,
                                color = MaterialTheme.colorScheme.primary,
                                shape = RoundedCornerShape(16.dp),
                            )
                        } else {
                            Modifier.border(
                                width = 0.5.dp,
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
                                shape = RoundedCornerShape(16.dp),
                            )
                        },
                    )
                    .alpha(if (isUnavailable) 0.55f else 1f),
                contentAlignment = Alignment.Center,
            ) {
                icon()
            }

            if (onRemoveClick != null) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHighest,
                    shadowElevation = 2.dp,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .offset(x = (-6).dp, y = (-6).dp)
                        .size(24.dp)
                        .clip(CircleShape)
                        .clickable(onClick = onRemoveClick)
                        .semantics { contentDescription = removeContentDescription },
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = "−",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }

            if (isSelected) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primary,
                    shadowElevation = 2.dp,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 6.dp, y = (-6).dp)
                        .size(22.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = "✓",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    }
                }
            }
        }

        if (showsName) {
            Text(
                text = name,
                style = MaterialTheme.typography.labelMedium,
                color = if (isUnavailable) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
internal fun HomeFolderIcon(
    apps: List<CatalogApp>,
    size: Dp = HomeGridMetrics.ICON_SIZE,
) {
    val inset = size * 0.14f
    val spacing = size * 0.06f
    val mini = (size - inset * 2f - spacing * 2f) / 3f
    val previewApps = apps.take(9)
    val shape = RoundedCornerShape(size * 0.24f)

    Box(
        modifier = Modifier
            .size(size)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .border(0.75.dp, MaterialTheme.colorScheme.outlineVariant, shape)
            .padding(inset),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
            for (row in 0 until 3) {
                Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                    for (col in 0 until 3) {
                        val idx = row * 3 + col
                        if (idx < previewApps.size) {
                            AppIconBadge(app = previewApps[idx], size = mini)
                        } else {
                            Spacer(modifier = Modifier.size(mini))
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun HomeDockPlatter(
    highlighted: Boolean = false,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
        tonalElevation = 2.dp,
        border = if (highlighted) {
            BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
        } else {
            BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        },
        modifier = modifier.fillMaxWidth(),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            content()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeFolderSheet(
    folder: HomeFolder,
    apps: List<CatalogApp>,
    onLaunchApp: (CatalogApp) -> Unit,
    onRenameFolder: (String) -> Unit,
    onReorderFolder: (List<String>) -> Unit,
    onRemoveFromFolder: (String) -> Unit,
    onDissolveFolder: () -> Unit,
    onDismiss: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    var renaming by remember { mutableStateOf(false) }
    var draftName by remember(folder.id, folder.name) { mutableStateOf(folder.name) }
    var organizing by remember { mutableStateOf(false) }
    var confirmDissolve by remember { mutableStateOf(false) }
    var menuForKey by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(apps.isEmpty()) {
        if (apps.isEmpty()) onDismiss()
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = folder.name,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() },
                )
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (renaming) {
                        TextButton(
                            onClick = {
                                onRenameFolder(draftName)
                                renaming = false
                            },
                        ) {
                            Text("保存名称")
                        }
                    } else if (organizing) {
                        TextButton(onClick = { organizing = false }) {
                            Text("完成")
                        }
                    } else {
                        TextButton(
                            onClick = {
                                draftName = folder.name
                                renaming = true
                            },
                        ) {
                            Text("重命名")
                        }
                        TextButton(onClick = { organizing = true }) {
                            Text("整理")
                        }
                        TextButton(
                            onClick = { confirmDissolve = true },
                            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                        ) {
                            Text("解散")
                        }
                    }
                }
            }

            if (renaming) {
                OutlinedTextField(
                    value = draftName,
                    onValueChange = { if (it.length <= HomeFolder.NAME_LIMIT) draftName = it },
                    label = { Text("文件夹名称") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (organizing) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    apps.forEachIndexed { index, app ->
                        Surface(
                            shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                AppIconBadge(app = app, size = 40.dp)
                                Text(
                                    text = app.name,
                                    style = MaterialTheme.typography.titleSmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                                TextButton(
                                    onClick = {
                                        val ids = folder.appIds.toMutableList()
                                        if (index > 0 && index < ids.size) {
                                            val item = ids.removeAt(index)
                                            ids.add(index - 1, item)
                                            onReorderFolder(ids)
                                        }
                                    },
                                    enabled = index > 0,
                                ) {
                                    Text("上移")
                                }
                                TextButton(
                                    onClick = {
                                        val ids = folder.appIds.toMutableList()
                                        if (index >= 0 && index + 1 < ids.size) {
                                            val item = ids.removeAt(index)
                                            ids.add(index + 1, item)
                                            onReorderFolder(ids)
                                        }
                                    },
                                    enabled = index + 1 < apps.size,
                                ) {
                                    Text("下移")
                                }
                                TextButton(
                                    onClick = { onRemoveFromFolder(app.homeKey) },
                                    colors = ButtonDefaults.textButtonColors(
                                        contentColor = MaterialTheme.colorScheme.error,
                                    ),
                                ) {
                                    Text("移出")
                                }
                            }
                        }
                    }
                }
            } else {
                BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                    val metrics = HomeGridMetrics.calculate(maxWidth)
                    val rows = apps.chunked(metrics.columns)
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(HomeGridMetrics.ROW_SPACING),
                    ) {
                        rows.forEach { rowApps ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(metrics.gap),
                            ) {
                                rowApps.forEach { app ->
                                    Box {
                                        HomeAppGlyph(
                                            name = app.name,
                                            labelWidth = metrics.labelWidth,
                                            isUnavailable = app.launchUrl == null,
                                            onClick = {
                                                onDismiss()
                                                onLaunchApp(app)
                                            },
                                            onLongClick = {
                                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                menuForKey = app.homeKey
                                            },
                                        ) {
                                            AppIconBadge(app = app, size = HomeGridMetrics.ICON_SIZE)
                                        }
                                        DropdownMenu(
                                            expanded = menuForKey == app.homeKey,
                                            onDismissRequest = { menuForKey = null },
                                        ) {
                                            DropdownMenuItem(
                                                text = { Text("移出“${folder.name}”") },
                                                onClick = {
                                                    menuForKey = null
                                                    onRemoveFromFolder(app.homeKey)
                                                },
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (confirmDissolve) {
                AlertDialog(
                    onDismissRequest = { confirmDissolve = false },
                    title = { Text("解散“${folder.name}”？") },
                    text = { Text("其中的应用会留在云居原来的位置。") },
                    confirmButton = {
                        Button(
                            onClick = {
                                confirmDissolve = false
                                onDissolveFolder()
                                onDismiss()
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                        ) {
                            Text("解散文件夹")
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = { confirmDissolve = false }) {
                            Text("取消")
                        }
                    },
                )
            }
        }
    }
}
