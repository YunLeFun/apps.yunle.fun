#!/usr/bin/env bash
#
# 一键应用 CloudBase NoSQL 集合安全规则到生产环境
#
# 用法：
#   bash scripts/cloudbase-rules/apply.sh
#
# 前提：
#   - config/mcporter.json 已配置 CloudBase MCP
#   - 已通过 device-code 登录 CloudBase（`npx mcporter call cloudbase auth action=status` 显示 READY）
#
# 规则文档：docs/dev/cloudbase-rules.md

set -euo pipefail

ENV_ID="yunlefun-8g7ybcxc7345c490"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 选择环境 $ENV_ID"
npx mcporter call cloudbase auth action=set_env envId="$ENV_ID" >/dev/null

for f in apps app_submissions app_review_events app_submitters app_identifiers public_market_listings personal_workshops workshop_memberships workshop_events user_home_screens featured_apps weekly_charts app_reviews app_reports moderation_tasks diagnostic_log_uploads; do
  echo "==> 应用 $f 规则"
  npx mcporter call cloudbase managePermissions --args "$(cat "$SCRIPT_DIR/$f.json")" \
    | grep -E '"Success"|"message"' | head -3
done

echo
echo "==> 校验所有集合规则"
for f in apps app_submissions app_review_events app_submitters app_identifiers public_market_listings personal_workshops workshop_memberships workshop_events user_home_screens featured_apps weekly_charts app_reviews app_reports moderation_tasks diagnostic_log_uploads; do
  echo "--- $f ---"
  npx mcporter call cloudbase queryPermissions \
    action=getResourcePermission resourceType=noSqlDatabase resourceId="$f" \
    | grep -E '"Permission"|"SecurityRule"' | head -2
done

echo
echo "✅ 全部规则已同步"
