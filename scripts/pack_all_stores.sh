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
  if [[ "$ASSETS_ROOT" != /* ]]; then
    ASSETS_ROOT="$ROOT/$ASSETS_ROOT"
  fi
else
  ASSETS_ROOT="$ROOT"
fi

# Convert DIST_DIR to absolute path if relative
if [[ -n "${DIST_DIR:-}" ]]; then
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
require zipinfo
# Check for sha256 command (either sha256sum or shasum)
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "Missing sha256 command (need either 'sha256sum' or 'shasum')"
  exit 1
fi

# Helper functions
ensure_dir() {
  local path="$1"
  [[ ! -d "$path" ]] && mkdir -p "$path" || true
}

get_file_size() {
  local path="$1"
  if stat -c%s "$path" >/dev/null 2>&1; then
    stat -c%s "$path"  # Linux
  else
    stat -f%z "$path"  # macOS/BSD
  fi
}

get_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    echo "ERROR: No sha256 command found" >&2
    exit 1
  fi
}

encode_base64() {
  local path="$1"
  if base64 --version 2>&1 | grep -q GNU; then
    base64 -w 0 "$path"  # Linux
  else
    base64 -i "$path"     # macOS
  fi
}

generate_store_index_md() {
  local store_name="$1" store_index="$2" base_url="$3"
  local store_json_path="$DIST_DIR/$store_index"
  
  if [[ ! -f "$store_json_path" ]]; then
    return
  fi
  
  local item_count=$(jq -r ".items | length" "$store_json_path")
  if [[ "$item_count" -eq 0 ]]; then
    return
  fi
  
  local md_filename="${store_index%.json}_index.md"
  local md_path="$DIST_DIR/$md_filename"
  
  {
    echo "# $store_name"
    echo ""
    echo "This page contains all assets available in this store."
    echo ""
    echo "| Preview | Name | Version | Author | Example | Description |"
    echo "|---------|------|---------|--------|---------|-------------|"
    
    # Process each item
    # Pre-process base_url to remove trailing slash if present
    # Note: Not using 'local' here so it's accessible in the subshell created by the pipe
    base_url_clean="${base_url%/}"
    
    jq -r '.items[] | 
      "\(.image // "null")\t\(.title // "null")\t\(.version // "null")\t\(.author // "null")\t\(.example_url // "null")\t\(.description // "null")"
    ' "$store_json_path" | while IFS=$'\t' read -r image title version author example_url description; do
      
      # Handle image
      local image_cell="—"
      if [[ -n "$image" && "$image" != "null" ]]; then
        local image_url="$image"
        if [[ "$image_url" != http* ]]; then
          # Convert relative to absolute URL
          if [[ -n "$base_url_clean" ]]; then
            image_url="$base_url_clean/$image_url"
          fi
        fi
        # Escape parentheses in title for markdown image alt text
        local title_escaped="${title//\(/\\\(}"
        title_escaped="${title_escaped//\)/\\\)}"
        image_cell="![$title_escaped]($image_url)"
      fi
      
      # Handle title
      local title_cell="${title:-—}"
      
      # Handle version
      local version_cell="${version:-—}"
      
      # Handle author
      local author_cell="${author:-—}"
      
      # Handle example
      local example_cell="—"
      if [[ -n "$example_url" && "$example_url" != "null" ]]; then
        local example_link="$example_url"
        if [[ "$example_link" != http* ]]; then
          # Convert relative to absolute URL
          if [[ -n "$base_url_clean" ]]; then
            example_link="$base_url_clean/$example_link"
          fi
        fi
        example_cell="[Example]($example_link)"
      fi
      
      # Handle description (escape pipe characters and newlines for markdown table)
      local desc_cell="${description:-—}"
      desc_cell="${desc_cell//|/&#124;}"
      desc_cell="${desc_cell//$'\n'/ }"
      
      echo "| $image_cell | $title_cell | $version_cell | $author_cell | $example_cell | $desc_cell |"
    done
    
    echo ""
    echo "Total: $item_count items"
  } > "$md_path"
  
  echo "$md_filename"
}

# Build example HTML if needed
build_example_if_needed() {
  local example_path="$1"
  local author="$2"
  local id="$3"
  local version="$4"
  local asset_dir="$5"
  local title="$6"

  if [[ -z "$example_path" || "$example_path" == "null" ]]; then
    echo ""
    return
  fi

  local example_dir_name="${author}:${id}@${version}"
  local example_output_dir="$DIST_DIR/examples/$example_dir_name"
  local example_url="${BASE_URL:+$BASE_URL/}examples/$example_dir_name/index.html"

  # Check if example directory already exists with required files (restored from GitHub Pages)
  if [[ -d "$example_output_dir" && -f "$example_output_dir/index.html" && -f "$example_output_dir/dmloader.js" ]]; then
    echo "$example_url"
    return
  fi

  local collection_path_for_ini="$example_path"
  if [[ "$collection_path_for_ini" != /* ]]; then
    collection_path_for_ini="/$collection_path_for_ini"
  fi

  # Create temporary INI file
  local tmp_ini; tmp_ini="$(mktemp)"
  echo "[bootstrap]" > "$tmp_ini"
  echo "main_collection = $collection_path_for_ini" >> "$tmp_ini"

  ensure_dir "$example_output_dir"

  # Copy INI to root for deployer
  local ini_in_root="$ROOT/build_ini.ini"
  [[ -f "$ini_in_root" ]] && rm -f "$ini_in_root"
  cp "$tmp_ini" "$ini_in_root"

  # Build using deployer
  local deployer_url="https://raw.githubusercontent.com/Insality/defold-deployer/refs/heads/update/deployer.sh"
  if (cd "$ROOT" && curl -s "${deployer_url}" | bash -s hbr --settings ./build_ini.ini) >&2; then
    # Find the most recently created index.html
    local found_html=""
    found_html="$(find "$ROOT/dist/bundle" -name "index.html" -type f -path "*/_html/*" 2>/dev/null | head -1)"
    [[ -z "$found_html" ]] && found_html="$(find "$ROOT/dist/bundle" -name "index.html" -type f 2>/dev/null | head -1)"

    if [[ -n "$found_html" && -f "$found_html" ]]; then
      local src_dir; src_dir="$(dirname "$found_html")"
      ensure_dir "$example_output_dir"
      cp -r "$src_dir"/* "$example_output_dir/" 2>/dev/null || true

      if [[ -f "$example_output_dir/index.html" && -f "$example_output_dir/dmloader.js" ]]; then
        echo "$example_url"
      else
        echo ""
      fi
    else
      echo ""
    fi
  else
    echo ""
  fi

  # Cleanup
  rm -f "$tmp_ini" "$ini_in_root"
}

pack_folder_store() {
  local store_name="$1" store_index="$2" content_folder="$3"

  local src_dir="$ASSETS_ROOT/$content_folder"
  local out_index="$DIST_DIR/$store_index"

  echo "📦 Store: $store_name"

  local tmp_index
  tmp_index="$(mktemp)"
  jq -n '{items:[]}' > "$tmp_index"

  if [[ ! -d "$src_dir" ]]; then
    echo "⚠️  Directory '$src_dir' does not exist, writing empty index"
    cp "$tmp_index" "$out_index"
    return
  fi

  shopt -s nullglob
  local all_manifests=()
  for manifest in "$src_dir"/*/*.json "$src_dir"/*/*/*.json; do
    all_manifests+=("$manifest")
  done

  for manifest in "${all_manifests[@]}"; do
    local asset_dir; asset_dir="$(dirname "$manifest")"
    local asset_folder; asset_folder="$(basename "$asset_dir")"
    local name_no_ext; name_no_ext="$(basename "$manifest" .json)"

    if [[ "$asset_folder" != "$name_no_ext" ]]; then
      echo "  ⚠️  SKIP: $asset_folder != $name_no_ext"
      continue
    fi

    local id version title author description api author_url image_rel depends tags example
    id="$(jq -r '.id // "'$asset_folder'"' "$manifest")"
    version="$(jq -r '.version' "$manifest")"
    title="$(jq -r '.title // "'$id'"' "$manifest")"
    author="$(jq -r '.author // empty' "$manifest")"
    description="$(jq -r '.description // empty' "$manifest")"
    api="$(jq -r '.api // empty' "$manifest")"
    author_url="$(jq -r '.author_url // empty' "$manifest")"
    example="$(jq -r '.example // empty' "$manifest")"
    example_url="$(jq -r '.example_url // empty' "$manifest")"
    image_rel="$(jq -r '.image // empty' "$manifest")"
    depends="$(jq -c '.depends // []' "$manifest")"
    tags="$(jq -c '.tags // []' "$manifest")"

    if [[ -z "$version" || "$version" == "null" ]]; then
      echo "  ❌ ERROR: $author:$id@$version has no version" >&2
      exit 1
    fi

    if [[ -z "$author" || "$author" == "null" ]]; then
      echo "  ❌ ERROR: $author:$id@$version has no author" >&2
      exit 1
    fi

    # Read content array
    local content_items=()
    if jq -e '.content' "$manifest" > /dev/null; then
      while IFS= read -r line; do
        content_items+=("$line")
      done < <(jq -r '.content[]' "$manifest")
    else
      while IFS= read -r line; do
        content_items+=("$line")
      done < <(cd "$asset_dir" && find . -maxdepth 1 -type f ! -name '*.json' ! -name '.*' -exec basename {} \;)
    fi

    if [[ ${#content_items[@]} -eq 0 ]]; then
      echo "  ❌ ERROR: $author:$id@$version has no content to pack" >&2
      exit 1
    fi

    # ZIP name format: author:id@version.zip
    local zip_name="${author}:${id}@${version}.zip"
    local zip_path="$DIST_DIR/$content_folder/$zip_name"

    ensure_dir "$(dirname "$zip_path")"

    # Create ZIP if it doesn't exist
    if [[ ! -f "$zip_path" ]]; then
      ( cd "$asset_dir" && zip -q -r "$zip_path" "${content_items[@]}" )
    fi

    if [[ ! -f "$zip_path" ]]; then
      echo "  ❌ ERROR: Failed to create ZIP at $zip_path" >&2
      exit 1
    fi

    # Extract list of files from ZIP archive (exclude directories)
    local zip_content
    zip_content="$(zipinfo -1 "$zip_path" | jq -R -s -c 'split("\n") | map(select(length > 0 and (. | endswith("/") | not)))')"

    local sha256 size zip_url image_url="" json_zip_url manifest_url api_url=""
    sha256="$(get_sha256 "$zip_path")"
    size="$(get_file_size "$zip_path")"
    zip_url="${BASE_URL:+$BASE_URL/}$content_folder/$zip_name"

    # Create base64 JSON version
    local json_zip_name="${zip_name}.json"
    local json_zip_path="$DIST_DIR/$content_folder/$json_zip_name"
    local base64_data="$(encode_base64 "$zip_path")"

    jq -n \
      --arg data "$base64_data" \
      --arg filename "$zip_name" \
      --arg size "$size" \
      --argjson content "$zip_content" \
      '{"data": $data, "filename": $filename, "size": ($size|tonumber), "content": $content}' \
      > "$json_zip_path"

    json_zip_url="${BASE_URL:+$BASE_URL/}$content_folder/$json_zip_name"

    # Copy manifest JSON to dist (with author to avoid conflicts)
    local manifest_dist_dir="$DIST_DIR/manifests/$content_folder/$author"
    ensure_dir "$manifest_dist_dir"
    cp -f "$manifest" "$manifest_dist_dir/${id}.json"
    manifest_url="${BASE_URL:+$BASE_URL/}manifests/$content_folder/$author/${id}.json"

    # Copy image if exists (with author to avoid conflicts)
    if [[ -n "$image_rel" && -f "$asset_dir/$image_rel" ]]; then
      local image_dir="$DIST_DIR/images/$author/$id"
      ensure_dir "$image_dir"
      cp -f "$asset_dir/$image_rel" "$image_dir/"
      local img_name; img_name="$(basename "$image_rel")"
      image_url="${BASE_URL:+$BASE_URL/}images/$author/$id/$img_name"
    fi

    # Generate GitHub URL for API documentation
    if [[ -n "$api" ]]; then
      if [[ "$api" =~ ^https?:// ]]; then
        api_url="$api"
      elif [[ -f "$asset_dir/$api" ]]; then
        local relative_path="${asset_dir#$ASSETS_ROOT/}/$api"
        api_url="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/blob/$GITHUB_BRANCH/$relative_path"
      fi
    fi

    # Build example if specified and example_url is not already set
    if [[ -z "$example_url" || "$example_url" == "null" ]]; then
      if [[ -n "$example" && "$example" != "null" ]]; then
        local built_example_url
        built_example_url="$(build_example_if_needed "$example" "$author" "$id" "$version" "$asset_dir" "$title")"
        [[ -n "$built_example_url" ]] && example_url="$built_example_url"
      fi
    fi

    # Build item JSON with all fields
    local item
    item="$(jq -n \
      --arg id "$id" --arg version "$version" --arg title "$title" \
      --arg author "$author" --arg description "$description" \
      --arg api "$api_url" --arg author_url "$author_url" --arg example_url "$example_url" \
      --arg image "$image_url" --arg zip_url "$zip_url" --arg json_zip_url "$json_zip_url" --arg sha256 "$sha256" \
      --arg manifest_url "$manifest_url" --arg size "$size" \
      --argjson depends "$depends" --argjson tags "$tags" \
      '{ id:$id, version:$version, title:$title,
         author:(if $author == "" then null else $author end),
         description:(if $description == "" then null else $description end),
         api:(if $api == "" then null else $api end),
         author_url:(if $author_url == "" then null else $author_url end),
         image:(if $image == "" then null else $image end),
         example_url:(if $example_url == "" then null else $example_url end),
         manifest_url:$manifest_url,
         zip_url:$zip_url, json_zip_url:$json_zip_url, sha256:$sha256, size:($size|tonumber),
         depends:$depends, tags:$tags }')"

    # Add item to items array
    jq --argjson item "$item" '.items += [$item]' "$tmp_index" > "${tmp_index}.tmp" && mv "${tmp_index}.tmp" "$tmp_index"

    # Compact output: author:id@version with all URLs (one per line)
    echo "  ✅ $author:$id@$version"
    echo "     zip: $zip_url"
    echo "     json: $json_zip_url"
    echo "     manifest: $manifest_url"
    [[ -n "$image_url" ]] && echo "     image: $image_url"
    [[ -n "$api_url" ]] && echo "     api: $api_url"
    [[ -n "$example_url" ]] && echo "     example: $example_url"
  done

  cp "$tmp_index" "$out_index"
  local item_count=$(jq -r ".items | length" "$out_index")
  echo "  📊 Total: $item_count items"
  
  # Generate markdown index
  local md_filename
  md_filename="$(generate_store_index_md "$store_name" "$store_index" "$BASE_URL")"
  if [[ -n "$md_filename" ]]; then
    echo "  📄 Store index: ${BASE_URL:+$BASE_URL/}$md_filename"
  fi
}

copy_or_stub_defold_deps() {
  local store_name="$1" store_index="$2"
  local out_index="$DIST_DIR/$store_index"
  if [[ -f "$ROOT/store/$store_index" ]]; then
    cp "$ROOT/store/$store_index" "$out_index"
  else
    jq -n '{schema_version:1,"items":[]}' > "$out_index"
  fi
  echo "📦 Store: $store_name"
  
  # Generate markdown index
  local md_filename
  md_filename="$(generate_store_index_md "$store_name" "$store_index" "$BASE_URL")"
  if [[ -n "$md_filename" ]]; then
    echo "  📄 Store index: ${BASE_URL:+$BASE_URL/}$md_filename"
  fi
}

# ---------- main ----------
echo "╔════════════════════════════════════════════════════════╗"
echo "║         Defold Asset Store Builder                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

if [[ ! -f "$SRC_STORES_JSON" ]]; then
  echo "❌ ERROR: Missing $SRC_STORES_JSON" >&2
  exit 1
fi

# Build per-store indices
store_objs=()
while IFS= read -r line; do
  store_objs+=("$line")
done < <(jq -c '.stores[]' "$SRC_STORES_JSON")

md_files=()
for s in "${store_objs[@]}"; do
  name="$(jq -r '.name' <<<"$s")"
  type="$(jq -r '.type' <<<"$s")"
  index="$(jq -r '.index' <<<"$s")"
  content="$(jq -r '.content // empty' <<<"$s")"

  case "$type" in
    folder)
      if [[ -z "$content" ]]; then
        echo "❌ ERROR: Store '$name' missing 'content'" >&2
        exit 1
      fi
      pack_folder_store "$name" "$index" "$content"
      ;;
    defold-dependencies)
      copy_or_stub_defold_deps "$name" "$index"
      ;;
    *)
      echo "❌ ERROR: Unknown store type: $type (store '$name')" >&2
      exit 1
      ;;
  esac
  
  # Collect markdown filename
  md_filename="${index%.json}_index.md"
  if [[ -f "$DIST_DIR/$md_filename" ]]; then
    md_files+=("$md_filename")
  fi
done

echo ""
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

echo "✅ Build complete: $DIST_DIR/stores.json"
if [[ -n "$BASE_URL" ]]; then
  echo "🌐 Published at: $BASE_URL/stores.json"
fi

echo ""
if [[ ${#md_files[@]} -gt 0 ]]; then
  echo "📄 Generated store index pages:"
  for md_file in "${md_files[@]}"; do
    echo "   ${BASE_URL:+$BASE_URL/}$md_file"
  done
fi
