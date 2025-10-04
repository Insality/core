#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_STORES_JSON="$ROOT/stores.json"
ASSETS_ROOT="${ASSETS_ROOT:-$ROOT/assets}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
BASE_URL="${BASE_URL:-}"  # set by CI to Pages URL

mkdir -p "$DIST_DIR"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1'"; exit 1; }; }
require jq
require zip
require sha256sum

pluralize() {  # very light pluralizer for compatibility keys
  case "$1" in
    widget) echo "widgets";;
    system) echo "systems";;
    entity) echo "entities";;
    particle) echo "particles";;
    material) echo "materials";;
    asset) echo "assets";;
    *) echo "items";;
  esac
}

pack_folder_store() {
  local store_name="$1" store_index="$2" folder="$3"

  local src_dir="$ASSETS_ROOT/$folder"
  local out_index="$DIST_DIR/$store_index"
  local array_key="$(pluralize "$folder")"

  mkdir -p "$DIST_DIR/images/$folder"

  local tmp_index
  tmp_index="$(mktemp)"
  # dual keys for compatibility: array_key + 'items'
  jq -n --arg key "$array_key" '{schema_version:1} | .[$key]=[] | .items=[]' > "$tmp_index"

  # nothing to pack? still emit empty index
  [[ -d "$src_dir" ]] || { cp "$tmp_index" "$out_index"; echo "no '$src_dir', wrote empty $store_index"; return; }

  shopt -s nullglob
  for manifest in "$src_dir"/*/*.json; do
    local asset_dir; asset_dir="$(dirname "$manifest")"
    local asset_folder; asset_folder="$(basename "$asset_dir")"
    local name_no_ext; name_no_ext="$(basename "$manifest" .json)"
    [[ "$asset_folder" != "$name_no_ext" ]] && continue

    local id version title author license image_rel depends tags
    id="$(jq -r '.id // "'$asset_folder'"' "$manifest")"
    version="$(jq -r '.version' "$manifest")"
    title="$(jq -r '.title // "'$id'"' "$manifest")"
    author="$(jq -r '.author // empty' "$manifest")"
    license="$(jq -r '.license // empty' "$manifest")"
    image_rel="$(jq -r '.image // empty' "$manifest")"
    depends="$(jq -c '.depends // []' "$manifest")"
    tags="$(jq -c '.tags // []' "$manifest")"

    [[ -z "$version" || "$version" == "null" ]] && { echo "ERROR: $store_name/$id has no version" >&2; exit 1; }

    local files=()
    if jq -e '.files' "$manifest" > /dev/null; then
      mapfile -t files < <(jq -r '.files[]' "$manifest")
    else
      mapfile -t files < <(cd "$asset_dir" && find . -maxdepth 1 -type f ! -name '*.json' ! -name '.*' -printf '%P\n')
    fi
    [[ ${#files[@]} -eq 0 ]] && { echo "ERROR: $store_name/$id has no files to pack" >&2; exit 1; }

    local zip_name="${folder}-${id}-${version}.zip"
    local zip_path="$DIST_DIR/$zip_name"

    ( cd "$asset_dir" && zip -q -r "$zip_path" "${files[@]}" )

    local sha256 size zip_url image_url=""
    sha256="$(sha256sum "$zip_path" | awk '{print $1}')"
    size="$(stat -c%s "$zip_path")"
    zip_url="${BASE_URL:+$BASE_URL/}$zip_name"

    if [[ -n "$image_rel" && -f "$asset_dir/$image_rel" ]]; then
      mkdir -p "$DIST_DIR/images/$folder/$id"
      cp -f "$asset_dir/$image_rel" "$DIST_DIR/images/$folder/$id/"
      local img_name; img_name="$(basename "$image_rel")"
      image_url="${BASE_URL:+$BASE_URL/}images/$folder/$id/$img_name"
    fi

    local item
    item="$(jq -n \
      --arg id "$id" --arg version "$version" --arg title "$title" \
      --arg author "$author" --arg license "$license" \
      --arg image "$image_url" --arg zip_url "$zip_url" --arg sha256 "$sha256" \
      --argjson depends "$depends" --argjson tags "$tags" \
      '{ id:$id, version:$version, title:$title,
         author:( $author|select(length>0) ),
         license:( $license|select(length>0) ),
         image:( $image|select(length>0) ),
         zip_url:$zip_url, sha256:$sha256, size:'"$size"',
         depends:$depends, tags:$tags }')"

    # push into both keys (compat)
    jq --arg k "$array_key" --argjson item "$item" \
       '.[$k] += [$item] | .items += [$item]' "$tmp_index" > "${tmp_index}.tmp" && mv "${tmp_index}.tmp" "$tmp_index"

    echo "packed [$store_name] $id v$version → $zip_name"
  done

  cp "$tmp_index" "$out_index"
  echo "index → $store_index"
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
[[ -f "$SRC_STORES_JSON" ]] || { echo "Missing $SRC_STORES_JSON"; exit 1; }

# Build per-store indices
mapfile -t store_objs < <(jq -c '.stores[]' "$SRC_STORES_JSON")
for s in "${store_objs[@]}"; do
  name="$(jq -r '.name' <<<"$s")"
  type="$(jq -r '.type' <<<"$s")"
  index="$(jq -r '.index' <<<"$s")"
  folder="$(jq -r '.folder // empty' <<<"$s")"

  case "$type" in
    folder)
      if [[ -z "$folder" ]]; then echo "Store '$name' missing 'folder'"; exit 1; fi
      pack_folder_store "$name" "$index" "$folder"
      ;;
    defold-dependencies)
      copy_or_stub_defold_deps "$name" "$index"
      ;;
    *)
      echo "Unknown store type: $type (store '$name')"; exit 1;;
  esac
done

# Write *published* root stores.json with absolute index URLs
updated_at="$(date -u +%FT%TZ)"
jq --arg base "$BASE_URL" --arg updated_at "$updated_at" '
  { updated_at: $updated_at,
    stores: [ .stores[]
      | .index = ( ($base // "") + "/" + .index )
    ]
  }
' "$SRC_STORES_JSON" > "$DIST_DIR/stores.json"

echo "root → dist/stores.json"
