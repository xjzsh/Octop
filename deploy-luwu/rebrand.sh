#!/usr/bin/env bash
# =============================================================================
# 与上游合并后重放品牌替换（陆吾AI 白标）
#
# 用途：merge upstream/main 后，语言包会恢复成上游的 "Octop" 文案。
#       在 luwu 分支上跑本脚本，把品牌替换重新应用一遍，然后提交。
#
# 用法:
#   bash rebrand.sh        # 检查 + 替换 + 显示待提交文件
#   bash rebrand.sh -c     # 替换后自动 git commit
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
COMMIT=0
[ "${1:-}" = "-c" ] && COMMIT=1

# OctopBot 是功能名，先占位保护
brand() {
    local f="$1" zh="$2" en="$3"
    local dest="$zh"
    case "$f" in *en.json) dest="$en" ;; esac
    sed -i 's/OctopBot/__LUWUBOT__/g; s/Octop/'"$dest"'/g; s/__LUWUBOT__/'"$dest"'Bot/g' "$f"
}

FILES=(
    dashboard/src/locales/zh.json
    dashboard/src/locales/en.json
    src/octop/i18n/zh.json
    src/octop/i18n/en.json
)

echo "── 替换语言包品牌文案"
for f in "${FILES[@]}"; do
    [ -f "$f" ] || { echo "跳过（不存在）: $f"; continue; }
    before=$(grep -c "Octop" "$f" || true)
    brand "$f" "陆吾AI" "Luwu AI"
    after=$(grep -c "Octop" "$f" || true)
    echo "  $f: $before -> $after 处剩余 Octop"
done

# JSON 合法性校验
python - <<'PYEOF'
import json, sys
for f in ["dashboard/src/locales/zh.json", "dashboard/src/locales/en.json",
          "src/octop/i18n/zh.json", "src/octop/i18n/en.json"]:
    try:
        json.load(open(f, encoding="utf-8"))
    except FileNotFoundError:
        continue
    except Exception as e:
        print(f"❌ {f} JSON 损坏: {e}"); sys.exit(1)
print("✅ JSON 校验通过")
PYEOF

if [ "$COMMIT" = 1 ]; then
    git add "${FILES[@]}"
    git commit -m "chore(brand): re-apply LuwuAI branding after upstream merge" || echo "（无改动需要提交）"
else
    echo ""
    echo "下一步:"
    echo "  git add ${FILES[*]}"
    echo "  git commit -m 'chore(brand): re-apply LuwuAI branding after upstream merge'"
    echo "  git push origin luwu"
fi
