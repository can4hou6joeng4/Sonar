package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.ui.theme.LocalSonarPalette

/** 弹层通用标题（歌单选择、音质、导入等面板共用）。 */
@Composable
fun SheetHeader(title: String, subtitle: String? = null) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(top = 14.dp, bottom = 10.dp),
    ) {
        Text(
            text = title,
            color = palette.ink,
            fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 28.sp,
        )
        if (subtitle != null) {
            Spacer(Modifier.height(5.dp))
            Text(
                text = subtitle,
                color = palette.secondaryInk,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                lineHeight = 16.sp,
                maxLines = 1,
            )
        }
    }
}
