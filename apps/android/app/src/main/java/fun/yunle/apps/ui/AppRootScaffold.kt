package `fun`.yunle.apps.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import `fun`.yunle.apps.R

internal enum class AppTab(
    val label: String,
    val iconRes: Int,
) {
    HOME("云居", R.drawable.ic_tab_home),
    GAMES("寻乐", R.drawable.ic_tab_games),
    WORKSHOP("工坊", R.drawable.ic_tab_workshop),
    ME("我", R.drawable.ic_tab_me),
}

@Composable
internal fun AppRootScaffold(
    selectedTab: AppTab,
    useNavigationRail: Boolean,
    onSelectTab: (AppTab) -> Unit,
    content: @Composable () -> Unit,
) {
    if (useNavigationRail) {
        Scaffold(
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            containerColor = MaterialTheme.colorScheme.surface,
        ) { innerPadding ->
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .consumeWindowInsets(innerPadding),
            ) {
                NavigationRail(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                ) {
                    AppTab.entries.forEach { tab ->
                        NavigationRailItem(
                            selected = selectedTab == tab,
                            onClick = { onSelectTab(tab) },
                            icon = {
                                Icon(
                                    painter = painterResource(tab.iconRes),
                                    contentDescription = tab.label,
                                )
                            },
                            label = { Text(tab.label) },
                            alwaysShowLabel = true,
                        )
                    }
                }
                VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight(),
                ) {
                    content()
                }
            }
        }
    } else {
        Scaffold(
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            bottomBar = {
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                ) {
                    AppTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = selectedTab == tab,
                            onClick = { onSelectTab(tab) },
                            icon = {
                                Icon(
                                    painter = painterResource(tab.iconRes),
                                    contentDescription = null,
                                )
                            },
                            label = { Text(tab.label) },
                            alwaysShowLabel = true,
                        )
                    }
                }
            },
            containerColor = MaterialTheme.colorScheme.surface,
        ) { innerPadding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .consumeWindowInsets(innerPadding),
            ) {
                content()
            }
        }
    }
}
