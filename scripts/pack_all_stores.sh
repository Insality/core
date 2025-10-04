#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_STORES_JSON="$ROOT/stores.json"

# GitHub repository info (can be overridden by environment variables)
GITHUB_OWNER="${GITHUB_OWNER:-Insality}"
GITHUB_REPO="${GITHUB_REPO:-core}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

# Convert ASSETS_ROOT to absolute path if relative
if [[ -n "${ASSETS_ROOT:-}" ]]; then
  # Handle relative paths
  if [[ "$ASSETS_ROOT" != /* ]]; then
    ASSETS_ROOT="$ROOT/$ASSETS_ROOT"
  fi
else
  ASSETS_ROOT="$ROOT"
fi

# Convert DIST_DIR to absolute path if relative
if [[ -n "${DIST_DIR:-}" ]]; then
  # Handle relative paths
  if [[ "$DIST_DIR" != /* ]]; then
    DIST_DIR="$ROOT/$DIST_DIR"
  fi
else
  DIST_DIR="$ROOT/dist"
fi

# Create dist directory
mkdir -p "$DIST_DIR"

BASE_URL="${BASE_URL:-}"  # set by CI to Pages URL

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1'"; exit 1; }; }
require jq
require zip
# Check for sha256 command (either sha256sum or shasum)
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "Missing sha256 command (need either 'sha256sum' or 'shasum')"
  exit 1
fi

pack_folder_store() {
  local store_name="$1" store_index="$2" content_folder="$3"

  local src_dir="$ASSETS_ROOT/$content_folder"
  local out_index="$DIST_DIR/$store_index"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Packing store: $store_name"
  echo "   content: $content_folder"
  echo "   src_dir: $src_dir"
  echo "   out_index: $out_index"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local tmp_index
  tmp_index="$(mktemp)"
  # Simple structure: just items array
  jq -n '{items:[]}' > "$tmp_index"

  # nothing to pack? still emit empty index
  if [[ ! -d "$src_dir" ]]; then
    echo "⚠️  Directory '$src_dir' does not exist, writing empty index"
    cp "$tmp_index" "$out_index"
    echo "✅ Wrote empty $store_index"
    return
  fi

  echo "📂 Searching for manifests in: $src_dir"
  echo "   Pattern: $src_dir/*/*.json and $src_dir/*/*/*.json"

  shopt -s nullglob
  local all_manifests=()
  # Support both 2-level (widget/fps_panel/) and 3-level (widget/insality/fps_panel/)
  for manifest in "$src_dir"/*/*.json "$src_dir"/*/*/*.json; do
    all_manifests+=("$manifest")
  done

  # Sort manifests by modification time (oldest first)
  if [[ ${#all_manifests[@]} -gt 0 ]]; then
    local sorted_manifests
    sorted_manifests="$(printf '%s\n' "${all_manifests[@]}" | xargs ls -tr)"
    all_manifests=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && all_manifests+=("$line")
    done <<< "$sorted_manifests"
  fi

  echo "   Found ${#all_manifests[@]} manifest(s) (sorted by modification time)"

  for manifest in "${all_manifests[@]}"; do
    echo ""
    echo "─────────────────────────────────────────────────────"
    echo "📄 Processing: $manifest"
    local asset_dir; asset_dir="$(dirname "$manifest")"
    local asset_folder; asset_folder="$(basename "$asset_dir")"
    local name_no_ext; name_no_ext="$(basename "$manifest" .json)"

    echo "   asset_dir: $asset_dir"
    echo "   asset_folder: $asset_folder"
    echo "   name_no_ext: $name_no_ext"

    if [[ "$asset_folder" != "$name_no_ext" ]]; then
      echo "   ⚠️  SKIP: folder name '$asset_folder' != manifest name '$name_no_ext'"
      continue
    fi

    local id version title author description api author_url image_rel depends tags
    id="$(jq -r '.id // "'$asset_folder'"' "$manifest")"
    version="$(jq -r '.version' "$manifest")"
    title="$(jq -r '.title // "'$id'"' "$manifest")"
    author="$(jq -r '.author // empty' "$manifest")"
    description="$(jq -r '.description // empty' "$manifest")"
    api="$(jq -r '.api // empty' "$manifest")"
    author_url="$(jq -r '.author_url // empty' "$manifest")"
    image_rel="$(jq -r '.image // empty' "$manifest")"
    depends="$(jq -c '.depends // []' "$manifest")"
    tags="$(jq -c '.tags // []' "$manifest")"

    echo "   📋 id: $id"
    echo "   📋 version: $version"
    echo "   📋 title: $title"
    echo "   📋 author: $author"

    if [[ -z "$version" || "$version" == "null" ]]; then
      echo "   ❌ ERROR: $store_name/$id has no version" >&2
      exit 1
    fi

    if [[ -z "$author" || "$author" == "null" ]]; then
      echo "   ❌ ERROR: $store_name/$id has no author" >&2
      exit 1
    fi

    # Read content array (new field name instead of files)
    local content_items=()
    if jq -e '.content' "$manifest" > /dev/null; then
      echo "   📝 Using content from manifest"
      while IFS= read -r line; do
        content_items+=("$line")
      done < <(jq -r '.content[]' "$manifest")
    else
      echo "   📝 Auto-detecting files in directory"
      while IFS= read -r line; do
        content_items+=("$line")
      done < <(cd "$asset_dir" && find . -maxdepth 1 -type f ! -name '*.json' ! -name '.*' -exec basename {} \;)
    fi

    echo "   📦 Content to pack (${#content_items[@]}):"
    for f in "${content_items[@]}"; do
      echo "      - $f"
    done

    if [[ ${#content_items[@]} -eq 0 ]]; then
      echo "   ❌ ERROR: $store_name/$id has no content to pack" >&2
      exit 1
    fi

    # ZIP name format: author:id@version.zip in content_folder/
    local zip_name="${author}:${id}@${version}.zip"
    local zip_path="$DIST_DIR/$content_folder/$zip_name"

    echo "   🗜️  Creating ZIP: $content_folder/$zip_name"
    echo "   📍 ZIP path: $zip_path"
    echo "   📍 Working dir for zip: $asset_dir"

    # Ensure directory exists before creating ZIP
    mkdir -p "$(dirname "$zip_path")"

    # Create ZIP (will overwrite if exists)
    ( cd "$asset_dir" && zip -q -r "$zip_path" "${content_items[@]}" )

    if [[ ! -f "$zip_path" ]]; then
      echo "   ❌ ERROR: Failed to create ZIP at $zip_path" >&2
      exit 1
    fi

    echo "   ✅ ZIP created successfully"

    local sha256 size zip_url image_url=""

    # Cross-platform sha256
    if command -v sha256sum >/dev/null 2>&1; then
      sha256="$(sha256sum "$zip_path" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      sha256="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
    else
      echo "   ❌ ERROR: No sha256 command found (tried sha256sum, shasum)" >&2
      exit 1
    fi

    # Cross-platform file size
    if stat -c%s "$zip_path" >/dev/null 2>&1; then
      size="$(stat -c%s "$zip_path")"  # Linux
    else
      size="$(stat -f%z "$zip_path")"  # macOS/BSD
    fi

    zip_url="${BASE_URL:+$BASE_URL/}$content_folder/$zip_name"

    echo "   🔐 SHA256: $sha256"
    echo "   📏 Size: $size bytes"
    echo "   🔗 ZIP URL: $zip_url"

    # Copy manifest JSON to dist
    local manifest_url=""
    local manifest_dist_dir="$DIST_DIR/manifests/$content_folder"
    mkdir -p "$manifest_dist_dir"
    cp -f "$manifest" "$manifest_dist_dir/${id}.json"
    manifest_url="${BASE_URL:+$BASE_URL/}manifests/$content_folder/${id}.json"
    echo "   📋 Manifest URL: $manifest_url"

    # Copy image if exists
    if [[ -n "$image_rel" && -f "$asset_dir/$image_rel" ]]; then
      echo "   🖼️  Copying image: $image_rel"
      local image_dir="$DIST_DIR/images/$id"
      mkdir -p "$image_dir"
      cp -f "$asset_dir/$image_rel" "$image_dir/"
      local img_name; img_name="$(basename "$image_rel")"
      image_url="${BASE_URL:+$BASE_URL/}images/$id/$img_name"
      echo "   🔗 Image URL: $image_url"
    else
      echo "   ℹ️  No image specified or found"
    fi

    # Generate GitHub URL for API documentation
    local api_url=""
    if [[ -n "$api" ]]; then
      # Check if it's already a full URL (starts with http:// or https://)
      if [[ "$api" =~ ^https?:// ]]; then
        api_url="$api"
        echo "   🔗 API URL (external): $api_url"
      elif [[ -f "$asset_dir/$api" ]]; then
        # Generate GitHub URL: get relative path from repo root
        local relative_path="${asset_dir#$ASSETS_ROOT/}/$api"
        api_url="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/blob/$GITHUB_BRANCH/$relative_path"
        echo "   🔗 API URL (GitHub): $api_url"
      else
        echo "   ⚠️  API file not found: $api"
      fi
    fi

    # Build item JSON with all fields
    local item
    item="$(jq -n \
      --arg id "$id" --arg version "$version" --arg title "$title" \
      --arg author "$author" --arg description "$description" \
      --arg api "$api_url" --arg author_url "$author_url" \
      --arg image "$image_url" --arg zip_url "$zip_url" --arg sha256 "$sha256" \
      --arg manifest_url "$manifest_url" \
      --argjson depends "$depends" --argjson tags "$tags" \
      '{ id:$id, version:$version, title:$title,
         author:( $author|select(length>0) ),
         description:( $description|select(length>0) ),
         api:( $api|select(length>0) ),
         author_url:( $author_url|select(length>0) ),
         image:( $image|select(length>0) ),
         manifest_url:$manifest_url,
         zip_url:$zip_url, sha256:$sha256, size:'"$size"',
         depends:$depends, tags:$tags }')"

    # Add item to items array
    jq --argjson item "$item" '.items += [$item]' "$tmp_index" > "${tmp_index}.tmp" && mv "${tmp_index}.tmp" "$tmp_index"

    echo "   ✅ packed [$store_name] $id v$version → $zip_name"
  done

  cp "$tmp_index" "$out_index"
  local item_count=$(jq -r ".items | length" "$out_index")
  echo ""
  echo "✅ Store complete: $store_name"
  echo "   📊 Total items: $item_count"
  echo "   📄 Index file: $store_index"
  echo ""
}

copy_or_stub_defold_deps() {
  local store_name="$1" store_index="$2"
  local out_index="$DIST_DIR/$store_index"
  # if you keep a handcrafted index in repo, copy it; otherwise write an empty stub
  if [[ -f "$ROOT/store/$store_index" ]]; then
    cp "$ROOT/store/$store_index" "$out_index"
  else
    jq -n '{schema_version:1,"items":[]}' > "$out_index"
  fi
  echo "defold-dependencies → $store_index"
}

# ---------- main ----------
echo "╔════════════════════════════════════════════════════════╗"
echo "║         Defold Asset Store Builder                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "🔧 Configuration:"
echo "   ROOT: $ROOT"
echo "   SRC_STORES_JSON: $SRC_STORES_JSON"
echo "   ASSETS_ROOT: $ASSETS_ROOT"
echo "   DIST_DIR: $DIST_DIR"
echo "   BASE_URL: ${BASE_URL:-<not set>}"
echo ""

if [[ ! -f "$SRC_STORES_JSON" ]]; then
  echo "❌ ERROR: Missing $SRC_STORES_JSON"
  echo "   Looking for: $SRC_STORES_JSON"
  echo "   Current dir: $(pwd)"
  ls -la "$ROOT/" 2>/dev/null || true
  exit 1
fi

echo "✅ Found stores.json"
echo ""

# Build per-store indices
store_objs=()
while IFS= read -r line; do
  store_objs+=("$line")
done < <(jq -c '.stores[]' "$SRC_STORES_JSON")

echo "📚 Processing ${#store_objs[@]} store(s)..."
echo ""

for s in "${store_objs[@]}"; do
  name="$(jq -r '.name' <<<"$s")"
  type="$(jq -r '.type' <<<"$s")"
  index="$(jq -r '.index' <<<"$s")"
  content="$(jq -r '.content // empty' <<<"$s")"

  case "$type" in
    folder)
      if [[ -z "$content" ]]; then
        echo "❌ ERROR: Store '$name' missing 'content'"
        exit 1
      fi
      pack_folder_store "$name" "$index" "$content"
      ;;
    defold-dependencies)
      copy_or_stub_defold_deps "$name" "$index"
      ;;
    *)
      echo "❌ ERROR: Unknown store type: $type (store '$name')"
      exit 1
      ;;
  esac
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Writing root stores.json..."

# Write *published* root stores.json with absolute index URLs
updated_at="$(date -u +%FT%TZ)"
jq --arg base "$BASE_URL" --arg updated_at "$updated_at" '
  { updated_at: $updated_at,
    stores: [ .stores[]
      | .index = ( ($base // "") + "/" + .index )
    ]
  }
' "$SRC_STORES_JSON" > "$DIST_DIR/stores.json"

echo "✅ Root index written: dist/stores.json"
echo ""

echo "╔════════════════════════════════════════════════════════╗"
echo "║             🎉 Build Complete! 🎉                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Artifacts in: $DIST_DIR"
echo ""
if [[ -n "$BASE_URL" ]]; then
  echo "🌐 Published URLs will be at:"
  echo "   $BASE_URL/stores.json"
  echo ""
fi
echo "Contents of dist:"
ls -lh "$DIST_DIR/" 2>/dev/null || true
echo ""
