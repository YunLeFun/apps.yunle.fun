package `fun`.yunle.apps.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import `fun`.yunle.apps.CatalogApp
import `fun`.yunle.apps.home.HomeEditOrder
import `fun`.yunle.apps.home.HomeFolder
import `fun`.yunle.apps.home.HomeGridItem
import `fun`.yunle.apps.ui.catalog.AppIconBadge
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.roundToInt

private enum class HomeEditSection {
    DOCK,
    MAIN,
}

private data class EditHoverTarget(
    val key: String,
    val merge: Boolean,
)

private data class EditDragState(
    val primary: HomeGridItem,
    val section: HomeEditSection,
    val point: Offset,
    val order: List<String>,
    val stack: List<CatalogApp>,
    val mergeTarget: String? = null,
) {
    val stackKeys: List<String> get() = stack.map { it.homeKey }
    val carriedApps: List<CatalogApp>
        get() = (primary.appOrNull?.let { listOf(it) } ?: emptyList()) + stack
}

@Composable
internal fun HomeEditCanvas(
    dock: List<CatalogApp>?,
    items: List<HomeGridItem>,
    reorderable: Set<String>,
    dockCapacity: Int = 4,
    onReorderDock: (List<String>) -> Unit,
    onReorderItems: (List<String>) -> Unit,
    onSetPinned: (List<CatalogApp>, Boolean) -> Boolean,
    onRemoveApp: (CatalogApp) -> Unit,
    onCreateFolder: (name: String, keys: List<String>, anchor: String) -> Unit,
    onAddToFolder: (folderId: String, keys: List<String>) -> Unit,
    onDissolveFolder: (HomeFolder) -> Unit,
    onOpenFolder: (HomeFolder) -> Unit,
    onExitEditMode: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    val tileCoords = remember { mutableStateMapOf<String, LayoutCoordinates>() }
    val sectionCoords = remember { mutableStateMapOf<HomeEditSection, LayoutCoordinates>() }
    var rootCoords by remember { mutableStateOf<LayoutCoordinates?>(null) }

    var dragState by remember { mutableStateOf<EditDragState?>(null) }
    var hoverTarget by remember { mutableStateOf<EditHoverTarget?>(null) }
    var dwellJob by remember { mutableStateOf<Job?>(null) }
    var settlingUntilMs by remember { mutableStateOf(0L) }
    var edgeScrollDirection by remember { mutableIntStateOf(0) }

    val selection = remember { mutableStateListOf<String>() }
    var selectionSection by remember { mutableStateOf(HomeEditSection.MAIN) }
    var dissolvingFolder by remember { mutableStateOf<HomeFolder?>(null) }

    val latestDock by rememberUpdatedState(dock)
    val latestItems by rememberUpdatedState(items)
    val latestReorderable by rememberUpdatedState(reorderable)

    val itemLookup = remember(items) { items.associateBy { it.id } }

    fun rootBoundsOf(coords: LayoutCoordinates?): Rect? {
        val root = rootCoords ?: return null
        if (coords == null || !coords.isAttached || !root.isAttached) return null
        return runCatching { root.localBoundingBoxOf(coords, clipBounds = false) }.getOrNull()
    }

    val visibleDock: List<CatalogApp>? = remember(dock, dragState) {
        val currentDock = dock ?: return@remember null
        val drag = dragState
        if (drag == null || drag.section != HomeEditSection.DOCK) {
            currentDock
        } else {
            val lookup = currentDock.associateBy { it.homeKey }.toMutableMap()
            drag.primary.appOrNull?.let { lookup[it.homeKey] = it }
            drag.order.mapNotNull { lookup[it] }
        }
    }

    val visibleMain: List<HomeGridItem> = remember(items, dragState) {
        val drag = dragState
        if (drag == null || drag.section != HomeEditSection.MAIN) {
            items
        } else {
            val lookup = itemLookup.toMutableMap()
            lookup[drag.primary.id] = drag.primary
            drag.order.mapNotNull { lookup[it] }
        }
    }

    val highlightedDock = remember(dragState?.point, rootCoords, sectionCoords[HomeEditSection.DOCK]) {
        val drag = dragState ?: return@remember false
        if (drag.section == HomeEditSection.DOCK) return@remember false
        rootBoundsOf(sectionCoords[HomeEditSection.DOCK])?.contains(drag.point) == true
    }

    val highlightedMain = remember(dragState?.point, rootCoords, sectionCoords[HomeEditSection.MAIN]) {
        val drag = dragState ?: return@remember false
        if (drag.section == HomeEditSection.MAIN) return@remember false
        rootBoundsOf(sectionCoords[HomeEditSection.MAIN])?.contains(drag.point) == true
    }

    LaunchedEffect(edgeScrollDirection) {
        if (edgeScrollDirection == 0) return@LaunchedEffect
        val stepPx = with(density) { 10.dp.toPx() }
        while (isActive && edgeScrollDirection != 0 && dragState != null) {
            scrollState.scrollBy(edgeScrollDirection * stepPx)
            delay(16L)
        }
    }

    fun toggleSelect(app: CatalogApp, section: HomeEditSection) {
        val key = app.homeKey
        if (selectionSection != section) {
            selection.clear()
            selectionSection = section
        }
        if (selection.contains(key)) {
            selection.remove(key)
        } else {
            selection.add(key)
        }
    }

    fun hitTile(point: Offset): Pair<HomeGridItem, HomeEditSection>? {
        val iconHalfPx = with(density) { (HomeGridMetrics.ICON_SIZE / 2).toPx() }
        val badgePadPx = with(density) { 8.dp.toPx() }
        val badgeSizePx = with(density) { 28.dp.toPx() }
        val candidates = buildList {
            visibleDock?.forEach { add(HomeGridItem.App(it) to HomeEditSection.DOCK) }
            visibleMain.forEach { add(it to HomeEditSection.MAIN) }
        }
        for ((item, section) in candidates) {
            val rect = rootBoundsOf(tileCoords[item.id]) ?: continue
            if (!rect.contains(point)) continue
            val badgeLeft = (rect.center.x - iconHalfPx - badgePadPx).coerceAtLeast(rect.left)
            val badgeTop = (rect.top - badgePadPx).coerceAtLeast(rect.top)
            val inBadgeCorner = point.x <= badgeLeft + badgeSizePx && point.y <= badgeTop + badgeSizePx &&
                point.x >= badgeLeft
            if (inBadgeCorner) return null
            return item to section
        }
        return null
    }

    fun sectionKeys(section: HomeEditSection): List<String> = when (section) {
        HomeEditSection.DOCK -> latestDock.orEmpty().map { it.homeKey }
        HomeEditSection.MAIN -> latestItems.map { it.id }
    }

    fun appForKey(key: String, section: HomeEditSection): CatalogApp? = when (section) {
        HomeEditSection.DOCK -> latestDock.orEmpty().firstOrNull { it.homeKey == key }
        HomeEditSection.MAIN -> latestItems.firstOrNull { it.id == key }?.appOrNull
    }

    fun cancelHover() {
        hoverTarget = null
        dwellJob?.cancel()
        dwellJob = null
    }

    fun updateHover(point: Offset) {
        val drag = dragState ?: return
        val otherSection = if (drag.section == HomeEditSection.DOCK) HomeEditSection.MAIN else HomeEditSection.DOCK
        val overOtherSection = drag.primary is HomeGridItem.App &&
            rootBoundsOf(sectionCoords[otherSection])?.contains(point) == true

        if (overOtherSection) {
            if (drag.mergeTarget != null) dragState = drag.copy(mergeTarget = null)
            cancelHover()
            return
        }

        val currentSectionItems: List<HomeGridItem> = when (drag.section) {
            HomeEditSection.DOCK -> visibleDock.orEmpty().map { HomeGridItem.App(it) }
            HomeEditSection.MAIN -> visibleMain
        }
        val hit = currentSectionItems.firstOrNull { candidate ->
            candidate.id != drag.primary.id &&
                rootBoundsOf(tileCoords[candidate.id])?.contains(point) == true
        }

        if (hit == null) {
            if (drag.mergeTarget != null) dragState = drag.copy(mergeTarget = null)
            cancelHover()
            return
        }

        val rect = rootBoundsOf(tileCoords[hit.id])!!
        val iconCenterY = rect.top + with(density) { (HomeGridMetrics.ICON_SIZE / 2).toPx() }
        val halfMergePx = with(density) { 20.dp.toPx() }
        val mergeBox = Rect(
            left = rect.center.x - halfMergePx,
            top = iconCenterY - halfMergePx,
            right = rect.center.x + halfMergePx,
            bottom = iconCenterY + halfMergePx,
        )
        val canMerge = drag.section == HomeEditSection.MAIN &&
            drag.primary is HomeGridItem.App &&
            mergeBox.contains(point)

        val nextHover = EditHoverTarget(key = hit.id, merge = canMerge)
        if (nextHover == hoverTarget) return

        if (drag.mergeTarget != null && (!canMerge || drag.mergeTarget != hit.id)) {
            dragState = drag.copy(mergeTarget = null)
        }
        hoverTarget = nextHover
        dwellJob?.cancel()
        dwellJob = scope.launch {
            if (canMerge) {
                delay(420L)
                val latest = dragState ?: return@launch
                if (hoverTarget == nextHover) {
                    dragState = latest.copy(mergeTarget = hit.id)
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                }
            } else {
                delay(160L)
                val now = System.currentTimeMillis()
                if (now < settlingUntilMs) return@launch
                val latest = dragState ?: return@launch
                if (hoverTarget != nextHover) return@launch
                if (latest.section == HomeEditSection.MAIN && !latestReorderable.contains(hit.id)) return@launch
                val targetIndex = latest.order.indexOf(hit.id)
                if (targetIndex < 0) return@launch
                val reordered = HomeEditOrder.moving(latest.primary.id, latest.order, targetIndex)
                if (reordered != latest.order) {
                    settlingUntilMs = now + 180L
                    dragState = latest.copy(order = reordered, mergeTarget = null)
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                }
            }
        }
    }

    fun commitDrag() {
        val drag = dragState ?: return
        cancelHover()
        edgeScrollDirection = 0
        dragState = null

        val mergeKey = drag.mergeTarget
        if (mergeKey != null && drag.primary is HomeGridItem.App && drag.section == HomeEditSection.MAIN) {
            val targetItem = latestItems.firstOrNull { it.id == mergeKey }
            val carriedKeys = drag.carriedApps.map { it.homeKey }
            when (targetItem) {
                is HomeGridItem.Folder -> onAddToFolder(targetItem.folder.id, carriedKeys)
                is HomeGridItem.App -> {
                    val allApps = drag.carriedApps + targetItem.app
                    val name = HomeGridItem.suggestedFolderName(allApps)
                    onCreateFolder(name, carriedKeys + targetItem.app.homeKey, targetItem.app.homeKey)
                }
                null -> Unit
            }
            selection.clear()
            return
        }

        val overDock = drag.section == HomeEditSection.MAIN &&
            latestDock != null &&
            rootBoundsOf(sectionCoords[HomeEditSection.DOCK])?.contains(drag.point) == true
        val overMain = drag.section == HomeEditSection.DOCK &&
            rootBoundsOf(sectionCoords[HomeEditSection.MAIN])?.contains(drag.point) == true

        if (overDock && drag.primary is HomeGridItem.App) {
            onSetPinned(drag.carriedApps, true)
            selection.clear()
            return
        }
        if (overMain && drag.primary is HomeGridItem.App) {
            onSetPinned(drag.carriedApps, false)
            selection.clear()
            return
        }

        val finalOrder = if (drag.stack.isNotEmpty()) {
            HomeEditOrder.landing(drag.stackKeys, drag.primary.id, drag.order)
        } else {
            drag.order
        }
        val original = sectionKeys(drag.section)
        if (finalOrder != original) {
            when (drag.section) {
                HomeEditSection.DOCK -> onReorderDock(finalOrder)
                HomeEditSection.MAIN -> onReorderItems(finalOrder)
            }
        }
        selection.clear()
    }

    val touchSlop = with(density) { 8.dp.toPx() }
    val edgeZonePx = with(density) { 72.dp.toPx() }

    Box(
        modifier = modifier
            .fillMaxSize()
            .onGloballyPositioned { rootCoords = it }
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { point ->
                        if (dragState == null && hitTile(point) == null) {
                            onExitEditMode()
                        }
                    },
                )
            }
            .pointerInput(dock, items, reorderable) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val target = hitTile(down.position) ?: return@awaitEachGesture
                    val (hitItem, hitSection) = target
                    if (hitSection == HomeEditSection.MAIN && !latestReorderable.contains(hitItem.id)) {
                        return@awaitEachGesture
                    }

                    val activePointer: PointerId = down.id
                    var releasedOrMoved = false
                    withTimeoutOrNull(140L) {
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == activePointer } ?: event.changes.firstOrNull()
                            if (change == null || !change.pressed) {
                                releasedOrMoved = true
                                break
                            }
                            if ((change.position - down.position).getDistance() > touchSlop) {
                                releasedOrMoved = true
                                break
                            }
                        }
                    }
                    if (releasedOrMoved) return@awaitEachGesture

                    // Pick up tile
                    val initialKeys = sectionKeys(hitSection)
                    val checkedInSection = if (hitItem is HomeGridItem.App &&
                        selectionSection == hitSection &&
                        selection.contains(hitItem.id)
                    ) {
                        selection.filter { it != hitItem.id }.mapNotNull { appForKey(it, hitSection) }
                    } else {
                        emptyList()
                    }
                    if (checkedInSection.isEmpty()) selection.clear()
                    val stackKeysSet = checkedInSection.mapTo(mutableSetOf()) { it.homeKey }
                    val draftOrder = initialKeys.filterNot { stackKeysSet.contains(it) }

                    dragState = EditDragState(
                        primary = hitItem,
                        section = hitSection,
                        point = down.position,
                        order = draftOrder,
                        stack = checkedInSection,
                    )
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)

                    var cancelled = false
                    try {
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val change = event.changes.firstOrNull { it.id == activePointer }
                                ?: event.changes.firstOrNull()
                                ?: break
                            if (change.changedToUpIgnoreConsumed() || !change.pressed) {
                                change.consume()
                                break
                            }
                            change.consume()
                            val point = change.position
                            dragState = dragState?.copy(point = point)
                            val rootH = rootCoords?.size?.height?.toFloat() ?: 0f
                            edgeScrollDirection = when {
                                point.y < edgeZonePx && scrollState.value > 0 -> -1
                                rootH > 0f && point.y > rootH - edgeZonePx -> 1
                                else -> 0
                            }
                            updateHover(point)
                        }
                    } catch (_: Throwable) {
                        cancelled = true
                    } finally {
                        if (cancelled) {
                            cancelHover()
                            edgeScrollDirection = 0
                            dragState = null
                        } else {
                            commitDrag()
                        }
                    }
                }
            },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState, enabled = dragState == null)
                .padding(horizontal = HomeGridMetrics.MARGIN, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            if (visibleDock != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .onGloballyPositioned { sectionCoords[HomeEditSection.DOCK] = it },
                ) {
                    HomeDockPlatter(highlighted = highlightedDock) {
                        if (visibleDock.isEmpty()) {
                            EditDropZoneHint(
                                text = "拖到这里设为常用（最多 $dockCapacity 个）",
                                highlighted = highlightedDock,
                            )
                        } else {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceEvenly,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                visibleDock.forEach { app ->
                                    key("edit_dock_${app.homeKey}") {
                                        val item = HomeGridItem.App(app)
                                        val lifted = dragState?.primary?.id == item.id
                                        val checked = selectionSection == HomeEditSection.DOCK &&
                                            selection.contains(item.id)
                                        EditGridTileSlot(
                                            itemKey = item.id,
                                            tileCoords = tileCoords,
                                            lifted = lifted,
                                        ) {
                                            HomeAppGlyph(
                                                name = app.name,
                                                showsName = false,
                                                labelWidth = HomeGridMetrics.ICON_SIZE,
                                                isUnavailable = app.launchUrl == null,
                                                wobbling = !lifted,
                                                seedKey = item.id,
                                                isSelected = checked,
                                                onClick = { toggleSelect(app, HomeEditSection.DOCK) },
                                                onRemoveClick = { onRemoveApp(app) },
                                            ) {
                                                AppIconBadge(app = app, size = HomeGridMetrics.ICON_SIZE)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .onGloballyPositioned { sectionCoords[HomeEditSection.MAIN] = it },
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "我的应用",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = "长按拖动排序 · 拖到图标上合并文件夹",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                if (visibleMain.isEmpty()) {
                    EditDropZoneHint(
                        text = "拖到这里取消常用",
                        highlighted = highlightedMain,
                    )
                } else {
                    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                        val metrics = HomeGridMetrics.calculate(maxWidth)
                        val rows = visibleMain.chunked(metrics.columns)
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(HomeGridMetrics.ROW_SPACING),
                        ) {
                            rows.forEach { rowItems ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(HomeGridMetrics.COLUMN_SPACING),
                                ) {
                                    for (column in 0 until metrics.columns) {
                                        val item = rowItems.getOrNull(column)
                                        if (item != null) {
                                            key("edit_main_${item.id}") {
                                                val lifted = dragState?.primary?.id == item.id
                                                val merging = dragState?.mergeTarget == item.id
                                                EditGridTileSlot(
                                                    itemKey = item.id,
                                                    tileCoords = tileCoords,
                                                    lifted = lifted,
                                                    modifier = Modifier.weight(1f),
                                                ) {
                                                    when (item) {
                                                        is HomeGridItem.App -> {
                                                            val checked = selectionSection == HomeEditSection.MAIN &&
                                                                selection.contains(item.id)
                                                            HomeAppGlyph(
                                                                name = item.app.name,
                                                                labelWidth = Dp.Unspecified,
                                                                isUnavailable = item.app.launchUrl == null,
                                                                wobbling = !lifted,
                                                                seedKey = item.id,
                                                                isSelected = checked,
                                                                isMergeTarget = merging,
                                                                onClick = { toggleSelect(item.app, HomeEditSection.MAIN) },
                                                                onRemoveClick = { onRemoveApp(item.app) },
                                                            ) {
                                                                AppIconBadge(
                                                                    app = item.app,
                                                                    size = HomeGridMetrics.ICON_SIZE,
                                                                )
                                                            }
                                                        }
                                                        is HomeGridItem.Folder -> {
                                                            HomeAppGlyph(
                                                                name = item.folder.name,
                                                                labelWidth = Dp.Unspecified,
                                                                wobbling = !lifted,
                                                                seedKey = item.id,
                                                                isMergeTarget = merging,
                                                                onClick = { onOpenFolder(item.folder) },
                                                                onRemoveClick = { dissolvingFolder = item.folder },
                                                                removeContentDescription = "解散 ${item.folder.name}",
                                                            ) {
                                                                HomeFolderIcon(
                                                                    apps = item.apps,
                                                                    size = HomeGridMetrics.ICON_SIZE,
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            Spacer(modifier = Modifier.weight(1f))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(64.dp))
        }

        // Floating dragged ghost overlay
        dragState?.let { drag ->
            val halfIconPx = with(density) { (HomeGridMetrics.ICON_SIZE / 2).toPx() }
            val behind = drag.stack.takeLast(2).reversed()
            Box(
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (drag.point.x - halfIconPx).roundToInt(),
                            (drag.point.y - halfIconPx).roundToInt(),
                        )
                    }
                    .graphicsLayer {
                        val s = if (drag.mergeTarget == null) 1.1f else 0.9f
                        scaleX = s
                        scaleY = s
                        shadowElevation = 14f
                    },
            ) {
                behind.forEachIndexed { index, app ->
                    Box(
                        modifier = Modifier
                            .offset(x = ((index + 1) * 5).dp, y = ((index + 1) * 3).dp)
                            .graphicsLayer { rotationZ = (index + 1) * 5f },
                    ) {
                        AppIconBadge(app = app, size = HomeGridMetrics.ICON_SIZE)
                    }
                }
                when (drag.primary) {
                    is HomeGridItem.App -> AppIconBadge(app = drag.primary.app, size = HomeGridMetrics.ICON_SIZE)
                    is HomeGridItem.Folder -> HomeFolderIcon(apps = drag.primary.apps, size = HomeGridMetrics.ICON_SIZE)
                }
                if (drag.stack.isNotEmpty()) {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .offset(x = 8.dp, y = (-8).dp)
                            .widthIn(min = 24.dp)
                            .heightIn(min = 24.dp),
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier.padding(horizontal = 6.dp),
                        ) {
                            Text(
                                text = "${drag.stack.size + 1}",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onPrimary,
                            )
                        }
                    }
                }
            }
        }
    }

    dissolvingFolder?.let { folder ->
        AlertDialog(
            onDismissRequest = { dissolvingFolder = null },
            title = { Text("解散“${folder.name}”？") },
            text = { Text("其中的应用会留在云居原来的位置。") },
            confirmButton = {
                Button(
                    onClick = {
                        dissolvingFolder = null
                        onDissolveFolder(folder)
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("解散文件夹")
                }
            },
            dismissButton = {
                TextButton(onClick = { dissolvingFolder = null }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun EditGridTileSlot(
    itemKey: String,
    tileCoords: MutableMap<String, LayoutCoordinates>,
    lifted: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    DisposableEffect(itemKey) {
        onDispose { tileCoords.remove(itemKey) }
    }
    Box(
        modifier = modifier
            .onGloballyPositioned { tileCoords[itemKey] = it }
            .alpha(if (lifted) 0f else 1f),
        contentAlignment = Alignment.TopCenter,
    ) {
        content()
    }
}

@Composable
private fun EditDropZoneHint(
    text: String,
    highlighted: Boolean,
) {
    val borderColor = if (highlighted) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.outlineVariant
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = HomeGridMetrics.ICON_SIZE)
            .drawBehind {
                drawRoundRect(
                    color = borderColor,
                    cornerRadius = CornerRadius(18.dp.toPx(), 18.dp.toPx()),
                    style = Stroke(
                        width = 1.5.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f), 0f),
                    ),
                )
            }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = if (highlighted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
