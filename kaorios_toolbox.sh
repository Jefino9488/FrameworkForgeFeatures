#@name Kaorios Toolbox
#@description Enables Play Integrity fix, Pixel spoofing, and unlimited Google Photos backup via Kaorios Toolbox framework patches
#@requires framework.jar

# ==================== MODULE CONFIGURATION ====================
# This script uses the add_to_module API to add files to the final module
# Usage: add_to_module <source_path> <dest_path_in_module> [type]
# Types: apk, xml, lib, file
#
# The following files will be added to the module:
# - KaoriosToolbox.apk → system/system_ext/priv-app/KaoriosToolbox/
# - Permission XML → system/system_ext/etc/permissions/
# - Native libraries (extracted from APK)
#
# You can customize the paths by modifying the add_to_module calls at the end


# ==================== SCRIPT CONFIGURATION ====================

FRAMEWORK="$FRAMEWORK_JAR"

if [ -z "$FRAMEWORK" ]; then
    echo "[!] ERROR: framework.jar not found"
    return 1
fi

# GitHub repository
KAORIOS_REPO="Wuang26/Kaorios-Toolbox"
KAORIOS_API_URL="https://api.github.com/repos/$KAORIOS_REPO/releases/latest"

# Work directories
FW_WORK_DIR="$TMP/fw_kaorios_dc"
KAORIOS_WORK_DIR="$TMP/kaorios_download"
UTILS_DIR="$KAORIOS_WORK_DIR/utils"
DEX_EXTRACT_DIR="$KAORIOS_WORK_DIR/dex_extract"

# ==================== HELPER FUNCTIONS ====================

# Get the last smali_classes directory
get_last_smali_dir() {
    local decompile_dir="$1"
    local target_smali_dir="smali"
    local max_num=0
    
    for dir in "$decompile_dir"/smali_classes*; do
        if [ -d "$dir" ]; then
            local num=$(basename "$dir" | sed 's/smali_classes//')
            if echo "$num" | grep -qE '^[0-9]+$' && [ "$num" -gt "$max_num" ]; then
                max_num=$num
                target_smali_dir="smali_classes${num}"
            fi
        fi
    done
    echo "$target_smali_dir"
}

# ==================== DOWNLOAD KAORIOS COMPONENTS ====================
# Downloads APK, classes.dex, and permission XML separately from GitHub releases

download_kaorios_components() {
    echo "[*] Fetching Kaorios Toolbox release information..."
    create_dir "$KAORIOS_WORK_DIR"
    create_dir "$UTILS_DIR"
    
    # Get release info using curl or wget
    local release_info="$KAORIOS_WORK_DIR/release.json"
    
    if command -v curl >/dev/null 2>&1; then
        curl -sL "$KAORIOS_API_URL" > "$release_info"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$release_info" "$KAORIOS_API_URL"
    else
        echo "[!] ERROR: Neither curl nor wget available"
        return 1
    fi
    
    if [ ! -f "$release_info" ] || [ ! -s "$release_info" ]; then
        echo "[!] ERROR: Failed to fetch release information from GitHub API"
        return 1
    fi
    
    # Extract version tag
    local version=$(grep -o '"tag_name": *"[^"]*"' "$release_info" | head -1 | sed 's/"tag_name": *"\(.*\)"/\1/')
    echo "[*] Latest version: $version"
    
    # Extract download URLs for individual assets
    local apk_url=$(grep -o '"browser_download_url": *"[^"]*KaoriosToolbox[^"]*\.apk"' "$release_info" | head -1 | sed 's/"browser_download_url": *"\(.*\)"/\1/')
    local xml_url=$(grep -o '"browser_download_url": *"[^"]*privapp_whitelist[^"]*\.xml"' "$release_info" | head -1 | sed 's/"browser_download_url": *"\(.*\)"/\1/')
    local dex_url=$(grep -o '"browser_download_url": *"[^"]*classes[^"]*\.dex"' "$release_info" | head -1 | sed 's/"browser_download_url": *"\(.*\)"/\1/')
    
    if [ -z "$apk_url" ] || [ -z "$xml_url" ]; then
        echo "[!] ERROR: Could not find required assets in release"
        echo "    APK URL: $apk_url"
        echo "    XML URL: $xml_url"
        return 1
    fi
    
    if [ -z "$dex_url" ]; then
        echo "[!] ERROR: classes.dex not found in release assets"
        echo "[!] The utility smali classes must come from classes.dex, not the APK"
        return 1
    fi
    
    echo "[*] Assets found:"
    echo "    APK: $(basename "$apk_url")"
    echo "    XML: $(basename "$xml_url")"
    echo "    DEX: $(basename "$dex_url")"
    
    # Download APK
    echo "[*] Downloading KaoriosToolbox.apk..."
    if command -v curl >/dev/null 2>&1; then
        curl -sL -o "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "$apk_url"
    else
        wget -q -O "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "$apk_url"
    fi
    
    if [ ! -f "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" ] || [ ! -s "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" ]; then
        echo "[!] ERROR: Failed to download APK"
        return 1
    fi
    
    # Download permission XML
    echo "[*] Downloading permission XML..."
    if command -v curl >/dev/null 2>&1; then
        curl -sL -o "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" "$xml_url"
    else
        wget -q -O "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" "$xml_url"
    fi
    
    if [ ! -f "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" ] || [ ! -s "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" ]; then
        echo "[!] ERROR: Failed to download permission XML"
        return 1
    fi
    
    # Download classes.dex (required for utility smali classes)
    echo "[*] Downloading classes.dex..."
    if command -v curl >/dev/null 2>&1; then
        curl -sL -o "$KAORIOS_WORK_DIR/classes.dex" "$dex_url"
    else
        wget -q -O "$KAORIOS_WORK_DIR/classes.dex" "$dex_url"
    fi
    
    if [ ! -f "$KAORIOS_WORK_DIR/classes.dex" ] || [ ! -s "$KAORIOS_WORK_DIR/classes.dex" ]; then
        echo "[!] ERROR: Failed to download classes.dex"
        return 1
    fi
    
    # Verify file sizes (must be > 100 bytes)
    for file in KaoriosToolbox.apk privapp_whitelist_com.kousei.kaorios.xml classes.dex; do
        local size=$(stat -c%s "$KAORIOS_WORK_DIR/$file" 2>/dev/null || stat -f%z "$KAORIOS_WORK_DIR/$file" 2>/dev/null)
        if [ -z "$size" ] || [ "$size" -lt 100 ]; then
            echo "[!] ERROR: $file is too small ($size bytes), download may have failed"
            return 1
        fi
    done
    
    # Store version
    echo "$version" > "$KAORIOS_WORK_DIR/version.txt"
    
    echo "[+] All Kaorios components downloaded successfully"
    return 0
}

# ==================== EXTRACT UTILITY CLASSES ====================
# Utility smali classes come from classes.dex, NOT from the APK
# Uses run_jar + baksmali from the DI environment to decompile DEX
# Downloads baksmali.jar if not found

# Use baksmali v2.5.2 (v2.x uses org.jf.baksmali.Main which works with dalvikvm)
# v3.x uses com.android.tools.smali.baksmali.Main which doesn't work with dalvikvm
BAKSMALI_VERSION="2.5.2"

extract_utility_classes() {
    echo "[*] Extracting Kaorios utility classes from classes.dex..."
    create_dir "$DEX_EXTRACT_DIR"
    create_dir "$DEX_EXTRACT_DIR/smali"
    
    local dex_path="$KAORIOS_WORK_DIR/classes.dex"
    
    if [ ! -f "$dex_path" ]; then
        echo "[!] ERROR: classes.dex not found at $dex_path"
        return 1
    fi
    
    # Find baksmali in DI environment or download it
    local baksmali_jar=""
    for jar in "$l"/baksmali*.jar "$DI_BIN"/baksmali*.jar /data/tmp/di/bin/baksmali*.jar "$TMP"/baksmali*.jar; do
        if [ -f "$jar" ]; then
            baksmali_jar="$jar"
            echo "[*] Found baksmali: $baksmali_jar"
            break
        fi
    done
    
    # If baksmali not found, download it
    if [ -z "$baksmali_jar" ]; then
        echo "[*] baksmali.jar not found, downloading v${BAKSMALI_VERSION}..."
        # URL format for v2.x: https://github.com/baksmali/smali/releases/download/v{version}/baksmali-{version}.jar
        local baksmali_download_url="https://github.com/baksmali/smali/releases/download/v${BAKSMALI_VERSION}/baksmali-${BAKSMALI_VERSION}.jar"
        baksmali_jar="$TMP/baksmali.jar"
        
        echo "[*] Downloading from: $baksmali_download_url"
        if command -v curl >/dev/null 2>&1; then
            curl -sL -o "$baksmali_jar" "$baksmali_download_url"
        else
            wget -q -O "$baksmali_jar" "$baksmali_download_url"
        fi
        
        if [ ! -f "$baksmali_jar" ] || [ ! -s "$baksmali_jar" ]; then
            echo "[!] ERROR: Failed to download baksmali.jar"
            echo "[*] Falling back to using apktool..."
            
            # Fallback: Create a minimal APK structure with the DEX
            local temp_apk="$KAORIOS_WORK_DIR/temp_dex.apk"
            
            # Create a minimal APK by just wrapping the DEX  
            # First create AndroidManifest.xml minimal content (just copy dex as-is in archive)
            create_dir "$KAORIOS_WORK_DIR/temp_apk"
            cp "$dex_path" "$KAORIOS_WORK_DIR/temp_apk/classes.dex"
            
            # Use DI's zip functionality (7za or similar)
            if command -v 7za >/dev/null 2>&1; then
                (cd "$KAORIOS_WORK_DIR/temp_apk" && 7za a -tzip "$temp_apk" classes.dex >/dev/null 2>&1)
            else
                # Try using apktool's internal zip via java
                echo "[!] Cannot create temp APK without 7za or zip"
                return 1
            fi
            
            if [ -f "$temp_apk" ]; then
                echo "[*] Using apktool to decompile DEX..."
                dynamic_apktool -decompile "$temp_apk" -o "$DEX_EXTRACT_DIR"
            else
                echo "[!] ERROR: Could not create temporary APK"
                return 1
            fi
        else
            echo "[+] Downloaded baksmali.jar successfully"
        fi
    fi
    
    # Use run_jar to invoke baksmali if we have it
    if [ -f "$baksmali_jar" ]; then
        echo "[*] Decompiling classes.dex using baksmali..."
        if run_jar "$baksmali_jar" d "$dex_path" -o "$DEX_EXTRACT_DIR/smali"; then
            echo "[+] baksmali completed successfully"
        else
            echo "[!] ERROR: baksmali failed to decompile classes.dex"
            return 1
        fi
    fi
    
    if [ ! -d "$DEX_EXTRACT_DIR/smali" ] || [ -z "$(ls -A "$DEX_EXTRACT_DIR/smali" 2>/dev/null)" ]; then
        echo "[!] ERROR: smali output directory is empty"
        ls -la "$DEX_EXTRACT_DIR/" 2>/dev/null
        return 1
    fi
    
    # Find utility classes in com/android/internal/util/kaorios (framework package)
    local utils_source=$(find "$DEX_EXTRACT_DIR" -type d -path "*/com/android/internal/util/kaorios" 2>/dev/null | head -1)
    
    if [ -z "$utils_source" ] || [ ! -d "$utils_source" ]; then
        echo "[!] ERROR: Could not find kaorios utility classes in decompiled DEX"
        echo "    Searched path: */com/android/internal/util/kaorios"
        echo "    Directory structure:"
        find "$DEX_EXTRACT_DIR" -type d -name "*kaorios*" 2>/dev/null | head -5
        find "$DEX_EXTRACT_DIR/smali" -type d 2>/dev/null | head -15
        return 1
    fi
    
    # Copy utility classes to our working directory
    create_dir "$UTILS_DIR"
    cp -r "$utils_source" "$UTILS_DIR/"
    
    local class_count=$(find "$UTILS_DIR/kaorios" -name "*.smali" 2>/dev/null | wc -l)
    echo "[+] Extracted $class_count utility classes from classes.dex"
    
    if [ "$class_count" -eq 0 ]; then
        echo "[!] ERROR: No smali files found after extraction"
        return 1
    fi
    
    return 0
}

# ==================== INJECT UTILITY CLASSES ====================

inject_kaorios_utility_classes() {
    local decompile_dir="$1"
    
    if [ ! -d "$UTILS_DIR/kaorios" ]; then
        echo "[!] ERROR: Utility classes not found at $UTILS_DIR/kaorios"
        return 1
    fi
    
    echo "[*] Injecting Kaorios utility classes into framework..."
    
    # Find the last smali_classes directory
    local target_smali_dir=$(get_last_smali_dir "$decompile_dir")
    echo "[*] Injecting into $target_smali_dir"
    
    # Create the package directory structure
    local target_dir="$decompile_dir/$target_smali_dir/com/android/internal/util/kaorios"
    create_dir "$target_dir"
    
    # Copy all utility classes
    cp -r "$UTILS_DIR/kaorios"/* "$target_dir/"
    
    local copied_count=$(find "$target_dir" -name "*.smali" | wc -l)
    echo "[+] Injected $copied_count Kaorios utility classes"
    
    return 0
}

# ==================== PATCH ApplicationPackageManager.hasSystemFeature ====================
# This is the most complex patch - follows Guide.md exactly

patch_application_package_manager() {
    local decompile_dir="$1"
    
    echo "[*] Patching ApplicationPackageManager.hasSystemFeature..."
    
    local target_file=$(find "$decompile_dir" -type f -path "*/android/app/ApplicationPackageManager.smali" | head -1)
    
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: ApplicationPackageManager.smali not found"
        return 0
    fi
    
    # Get the last smali directory for relocation
    local last_smali_dir=$(get_last_smali_dir "$decompile_dir")
    local current_dir=$(dirname "$target_file")
    local current_smali_root=$(echo "$target_file" | sed -E 's|(.*/(smali(_classes[0-9]*)?))/.+|\1|')
    local target_root="$decompile_dir/$last_smali_dir"
    
    # Relocate if not in last directory (to avoid DEX limit issues)
    if [ "$current_smali_root" != "$target_root" ]; then
        echo "[*] Relocating ApplicationPackageManager to $last_smali_dir..."
        create_dir "$target_root/android/app"
        mv "$current_dir"/ApplicationPackageManager*.smali "$target_root/android/app/" 2>/dev/null
        target_file="$target_root/android/app/ApplicationPackageManager.smali"
        echo "[+] Relocated ApplicationPackageManager"
    fi
    
    # Create the Kaorios block file (huge smali code block as per Guide.md)
    local kaorios_block_file="$TMP/kaorios_block.smali"
    cat > "$kaorios_block_file" << 'KAORIOS_BLOCK'
    invoke-static {}, Landroid/app/ActivityThread;->currentPackageName()Ljava/lang/String;

    move-result-object v0

    iget-object v1, p0, Landroid/app/ApplicationPackageManager;->mContext:Landroid/content/Context;

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getAppLog()Ljava/lang/String;

    move-result-object v2

    const/4 v3, 0x1

    invoke-static {v1, v2, v3}, Lcom/android/internal/util/kaorios/SettingsHelper;->isToggleEnabled(Landroid/content/Context;Ljava/lang/String;Z)Z

    move-result v1

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getFeaturesPixel()[Ljava/lang/String;

    move-result-object v2

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getFeaturesPixelOthers()[Ljava/lang/String;

    move-result-object v4

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getFeaturesTensor()[Ljava/lang/String;

    move-result-object v5

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getFeaturesNexus()[Ljava/lang/String;

    move-result-object v6

    if-eqz v0, :cond_9f

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackageGsa()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v7

    if-nez v7, :cond_6f

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackagePixelAgent()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v7

    if-nez v7, :cond_6f

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackagePixelCreativeAssistant()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v7

    if-nez v7, :cond_6f

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackagePixelDialer()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v7

    if-nez v7, :cond_6f

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackagePhotos()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v7

    if-eqz v7, :cond_9f

    if-nez v1, :cond_9f

    :cond_6f
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v7

    invoke-interface {v7, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v7

    if-eqz v7, :cond_7b

    goto/16 :goto_14d

    :cond_7b
    invoke-static {v4}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v7

    invoke-interface {v7, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v7

    if-eqz v7, :cond_87

    goto/16 :goto_14d

    :cond_87
    invoke-static {v5}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v7

    invoke-interface {v7, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v7

    if-eqz v7, :cond_93

    goto/16 :goto_14d

    :cond_93
    invoke-static {v6}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v7

    invoke-interface {v7, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v7

    if-eqz v7, :cond_9f

    goto/16 :goto_14d

    :cond_9f
    const/4 v7, 0x0

    if-eqz v0, :cond_dc

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackagePhotos()Ljava/lang/String;

    move-result-object v8

    invoke-virtual {v0, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v8

    if-eqz v8, :cond_dc

    if-eqz v1, :cond_dc

    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v1

    invoke-interface {v1, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :cond_b9

    goto :goto_cf

    :cond_b9
    invoke-static {v4}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v1

    invoke-interface {v1, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :cond_c5

    goto/16 :goto_14d

    :cond_c5
    invoke-static {v5}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v1

    invoke-interface {v1, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :cond_d0

    :goto_cf
    return v7

    :cond_d0
    invoke-static {v6}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v1

    invoke-interface {v1, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :cond_dc

    goto/16 :goto_14d

    :cond_dc
    iget-object p0, p0, Landroid/app/ApplicationPackageManager;->mContext:Landroid/content/Context;

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getSystemLog()Ljava/lang/String;

    move-result-object v1

    invoke-static {p0, v1, v7}, Lcom/android/internal/util/kaorios/SettingsHelper;->isToggleEnabled(Landroid/content/Context;Ljava/lang/String;Z)Z

    move-result p0

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getModelInfoProperty()Ljava/lang/String;

    move-result-object v1

    invoke-static {v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v1

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPixelTensorModelRegex()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v1, v7}, Ljava/lang/String;->matches(Ljava/lang/String;)Z

    move-result v1

    if-eqz v0, :cond_11e

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackageGoogleAs()Ljava/lang/String;

    move-result-object v7

    invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_11e

    if-eqz v1, :cond_10f

    invoke-static {v5}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v0

    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_10f

    goto :goto_14d

    :cond_10f
    if-nez v1, :cond_11e

    if-eqz p0, :cond_11e

    invoke-static {v5}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v0

    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_11e

    goto :goto_14d

    :cond_11e
    if-eqz p1, :cond_12d

    invoke-static {v5}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v0

    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_12d

    if-nez v1, :cond_12d

    return p0

    :cond_12d
    invoke-static {v6}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object p0

    invoke-interface {p0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result p0

    if-eqz p0, :cond_138

    goto :goto_14d

    :cond_138
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object p0

    invoke-interface {p0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result p0

    if-eqz p0, :cond_143

    goto :goto_14d

    :cond_143
    invoke-static {v4}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object p0

    invoke-interface {p0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result p0

    if-eqz p0, :cond_14e

    :goto_14d
    return v3

    :cond_14e
KAORIOS_BLOCK

    # Patch 1: Add mContext field if not exists
    if ! grep -q ".field private final mContext:Landroid/content/Context;" "$target_file"; then
        awk '
        /\.source/ {
            print $0
            print ""
            print ".field private final mContext:Landroid/content/Context;"
            next
        }
        { print $0 }
        ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
        echo "[+] Added mContext field"
    fi
    
    # Patch 2: Add constructor if not exists
    if ! grep -q ".method public constructor <init>(Landroid/content/Context;)V" "$target_file"; then
        awk '
        BEGIN { done = 0 }
        !done && /^\.method/ {
            print ".method public constructor <init>(Landroid/content/Context;)V"
            print "    .registers 2"
            print ""
            print "    invoke-direct {p0}, Ljava/lang/Object;-><init>()V"
            print ""
            print "    iput-object p1, p0, Landroid/app/ApplicationPackageManager;->mContext:Landroid/content/Context;"
            print ""
            print "    return-void"
            print ".end method"
            print ""
            done = 1
        }
        { print $0 }
        ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
        echo "[+] Added ApplicationPackageManager(Context) constructor"
    fi
    
    # Patch 3: Modify hasSystemFeature(String, int) method
    # - Change .locals X to .registers 12
    # - Insert Kaorios block ABOVE the mHasSystemFeatureCache line
    if ! grep -q "KaoriFeaturesUtils" "$target_file"; then
        awk -v blockfile="$kaorios_block_file" '
        BEGIN {
            in_method = 0
            method_patched = 0
            # Read the block file
            while ((getline line < blockfile) > 0) {
                block[++block_count] = line
            }
            close(blockfile)
        }
        
        # Entering hasSystemFeature(Ljava/lang/String;I)Z method
        /\.method.*hasSystemFeature\(Ljava\/lang\/String;I\)Z/ {
            in_method = 1
        }
        
        # Change .locals to .registers 12 inside the method
        in_method && /\.locals/ {
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print indent ".registers 12"
            next
        }
        
        # Insert Kaorios block ABOVE mHasSystemFeatureCache line
        in_method && /mHasSystemFeatureCache/ && /sget-object/ && !method_patched {
            # Print the Kaorios block first
            for (i = 1; i <= block_count; i++) {
                print block[i]
            }
            print ""
            method_patched = 1
        }
        
        # Exit method
        /\.end method/ {
            in_method = 0
        }
        
        { print $0 }
        ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
        echo "[+] Patched hasSystemFeature method with Kaorios logic block"
    else
        echo "[*] hasSystemFeature: Already patched"
    fi
    
    rm -f "$kaorios_block_file"
    return 0
}

# ==================== PATCH Instrumentation.newApplication ====================
# Guide: Find "return-object v0" before ".end method" and add invoke-static line above it

patch_instrumentation_new_application() {
    local decompile_dir="$1"
    
    echo "[*] Patching Instrumentation.newApplication methods..."
    
    local target_file=$(find "$decompile_dir" -type f -path "*/android/app/Instrumentation.smali" | head -1)
    
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: Instrumentation.smali not found"
        return 0
    fi
    
    if grep -q "ToolboxUtils;->KaoriosProps" "$target_file"; then
        echo "[*] Instrumentation.newApplication: Already patched"
        return 0
    fi
    
    # Patch both newApplication methods
    awk '
    BEGIN { 
        in_method = 0
        method_param = ""
    }
    
    # Entering newApplication method
    /\.method.*newApplication/ {
        if (/Ljava\/lang\/Class;Landroid\/content\/Context;/) {
            in_method = 1
            method_param = "p1"  # Context is p1
        } else if (/Ljava\/lang\/ClassLoader;Ljava\/lang\/String;Landroid\/content\/Context;/) {
            in_method = 1
            method_param = "p3"  # Context is p3
        }
    }
    
    # If in method and found return-object v0 right before .end method
    in_method && /return-object v0/ {
        # Store this line to print later
        return_line = $0
        # Get next line to check if its .end method
        if ((getline next_line) > 0) {
            if (next_line ~ /\.end method/) {
                # Get indentation
                match(return_line, /^[[:space:]]*/)
                indent = substr(return_line, RSTART, RLENGTH)
                
                # Print patch before return
                print ""
                printf "%sinvoke-static {%s}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosProps(Landroid/content/Context;)V\n", indent, method_param
                in_method = 0
                method_param = ""
            }
            # Print the stored return line and the next line
            print return_line
            print next_line
            next
        }
    }
    
    # Exit method
    /\.end method/ {
        in_method = 0
        method_param = ""
    }
    
    { print $0 }
    ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
    
    echo "[+] Patched Instrumentation.newApplication methods"
    return 0
}

# ==================== PATCH KeyStore2.getKeyEntry ====================
# Guide: Find "return-object v0" before ".end method" and add two lines above it

patch_keystore2_get_key_entry() {
    local decompile_dir="$1"
    
    echo "[*] Patching KeyStore2.getKeyEntry..."
    
    local target_file=$(find "$decompile_dir" -type f -path "*/android/security/KeyStore2.smali" | head -1)
    
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: KeyStore2.smali not found"
        return 0
    fi
    
    if grep -q "ToolboxUtils;->KaoriosKeybox" "$target_file"; then
        echo "[*] KeyStore2.getKeyEntry: Already patched"
        return 0
    fi
    
    awk '
    BEGIN { 
        in_method = 0
    }
    
    # Entering getKeyEntry method (not lambda)
    /\.method.*getKeyEntry/ && /KeyDescriptor/ && !/lambda/ {
        in_method = 1
    }
    
    # If in method and found return-object v0 right before .end method
    in_method && /return-object v0/ {
        return_line = $0
        if ((getline next_line) > 0) {
            if (next_line ~ /\.end method/) {
                match(return_line, /^[[:space:]]*/)
                indent = substr(return_line, RSTART, RLENGTH)
                
                # Print patch before return
                print ""
                printf "%sinvoke-static {v0}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosKeybox(Landroid/system/keystore2/KeyEntryResponse;)Landroid/system/keystore2/KeyEntryResponse;\n", indent
                printf "%smove-result-object v0\n", indent
                in_method = 0
            }
            print return_line
            print next_line
            next
        }
    }
    
    /\.end method/ {
        in_method = 0
    }
    
    { print $0 }
    ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
    
    echo "[+] Patched KeyStore2.getKeyEntry"
    return 0
}

# ==================== PATCH AndroidKeyStoreSpi.engineGetCertificateChain ====================
# Guide: 
# 1. Below ".registers XX" add invoke-static {} line
# 2. AFTER "aput-object v2, v3, v4" (which follows "const/4 v4, 0x0") add KaoriosKeybox

patch_android_keystore_spi() {
    local decompile_dir="$1"
    
    echo "[*] Patching AndroidKeyStoreSpi.engineGetCertificateChain..."
    
    local target_file=$(find "$decompile_dir" -type f -path "*/android/security/keystore2/AndroidKeyStoreSpi.smali" | head -1)
    
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: AndroidKeyStoreSpi.smali not found"
        return 0
    fi
    
    if grep -q "ToolboxUtils;->KaoriosPropsEngineGetCertificateChain" "$target_file"; then
        echo "[*] AndroidKeyStoreSpi.engineGetCertificateChain: Already patched"
        return 0
    fi
    
    awk '
    BEGIN { 
        in_method = 0
        patch1_done = 0
        look_for_aput = 0
    }
    
    # Entering engineGetCertificateChain method
    /\.method.*engineGetCertificateChain/ {
        in_method = 1
        patch1_done = 0
        look_for_aput = 0
    }
    
    in_method {
        # Patch 1: Add call after .registers or .locals
        if (!patch1_done && (/\.registers/ || /\.locals/)) {
            print $0
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print ""
            printf "%sinvoke-static {}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosPropsEngineGetCertificateChain()V\n", indent
            patch1_done = 1
            next
        }
        
        # Look for const/4 v4, 0x0 which precedes the aput-object we want to patch after
        if (/const\/4 v4, 0x0/) {
            look_for_aput = 1
        }
        
        # Patch 2: After aput-object v2, v3, v4
        if (look_for_aput && /aput-object v2, v3, v4/) {
            print $0
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print ""
            printf "%sinvoke-static {v3}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosKeybox([Ljava/security/cert/Certificate;)[Ljava/security/cert/Certificate;\n", indent
            printf "%smove-result-object v3\n", indent
            look_for_aput = 0
            next
        }
    }
    
    /\.end method/ {
        in_method = 0
    }
    
    { print $0 }
    ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
    
    echo "[+] Patched AndroidKeyStoreSpi.engineGetCertificateChain"
    return 0
}

# ==================== ADD MODULE EXTRAS ====================
# Uses the add_to_module API to register files for inclusion in the module
# These functions are provided by the DI environment (run.sh)

register_module_extras() {
    echo "[*] Registering module extras..."
    
    local apk_dest="system/system_ext/priv-app/KaoriosToolbox"
    local xml_dest="system/system_ext/etc/permissions"
    
    # Add APK to module
    if [ -f "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" ]; then
        add_to_module "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "$apk_dest/KaoriosToolbox.apk" "apk"
        
        # Extract and add native libraries from APK
        add_apk_libs "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "$apk_dest"
    fi
    
    # Add permission XML to module
    if [ -f "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" ]; then
        add_to_module "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" \
                      "$xml_dest/privapp_whitelist_com.kousei.kaorios.xml" "xml"
    fi
    
    return 0
}

# ==================== MAIN ====================

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Kaorios Toolbox Framework Patcher            ║"
echo "║   Play Integrity | Pixel Spoofing | GPhotos    ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

# Create work directories
create_dir "$KAORIOS_WORK_DIR"
create_dir "$FW_WORK_DIR"

# Step 1: Download Kaorios components (APK, DEX, XML separately)
echo "[*] Step 1: Downloading Kaorios Toolbox components..."
if ! download_kaorios_components; then
    echo "[!] ERROR: Failed to download Kaorios components"
    delete_recursive "$KAORIOS_WORK_DIR"
    return 1
fi

# Step 2: Extract utility classes from classes.dex (NOT from APK!)
echo ""
echo "[*] Step 2: Extracting utility classes from classes.dex..."
if ! extract_utility_classes; then
    echo "[!] ERROR: Failed to extract utility classes"
    delete_recursive "$KAORIOS_WORK_DIR"
    return 1
fi

# Step 3: Decompile framework.jar
echo ""
echo "[*] Step 3: Decompiling framework.jar..."
dynamic_apktool -decompile "$FRAMEWORK" -o "$FW_WORK_DIR"

if [ ! -d "$FW_WORK_DIR" ]; then
    echo "[!] ERROR: framework.jar decompilation failed"
    delete_recursive "$KAORIOS_WORK_DIR"
    return 1
fi

# Step 4: Inject utility classes
echo ""
echo "[*] Step 4: Injecting Kaorios utility classes..."
if ! inject_kaorios_utility_classes "$FW_WORK_DIR"; then
    echo "[!] ERROR: Failed to inject utility classes"
    delete_recursive "$FW_WORK_DIR"
    delete_recursive "$KAORIOS_WORK_DIR"
    return 1
fi

# Step 5: Apply framework patches
echo ""
echo "[*] Step 5: Applying Kaorios framework patches..."

patch_application_package_manager "$FW_WORK_DIR"
patch_instrumentation_new_application "$FW_WORK_DIR"
patch_keystore2_get_key_entry "$FW_WORK_DIR"
patch_android_keystore_spi "$FW_WORK_DIR"

# Step 6: Recompile framework.jar
echo ""
echo "[*] Step 6: Recompiling framework.jar..."
dynamic_apktool -recompile "$FW_WORK_DIR" -o "$FRAMEWORK"

if [ $? -ne 0 ]; then
    echo "[!] ERROR: framework.jar recompilation failed"
    delete_recursive "$FW_WORK_DIR"
    delete_recursive "$KAORIOS_WORK_DIR"
    return 1
fi

# Step 7: Register module extras (APK, XML, libs) using add_to_module API
echo ""
echo "[*] Step 7: Registering module extras..."
register_module_extras

# Cleanup decompiled framework (keep kaorios_work_dir for module generation)
delete_recursive "$FW_WORK_DIR"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   ✅ Kaorios Toolbox patches applied successfully!             ║"
echo "║                                                                ║"
echo "║   Patched (4/4 core patches):                                  ║"
echo "║   ✓ ApplicationPackageManager.hasSystemFeature                 ║"
echo "║     - mContext field, constructor, full Kaorios logic block    ║"
echo "║   ✓ Instrumentation.newApplication                             ║"
echo "║     - Property spoofing initialization                         ║"
echo "║   ✓ KeyStore2.getKeyEntry                                      ║"
echo "║     - Keybox attestation spoofing                              ║"
echo "║   ✓ AndroidKeyStoreSpi.engineGetCertificateChain               ║"
echo "║     - Certificate chain handling                               ║"
echo "║                                                                ║"
echo "║   Module extras registered via add_to_module API:              ║"
echo "║   • KaoriosToolbox.apk                                         ║"
echo "║   • Permission whitelist XML                                   ║"
echo "║   • Native libraries (extracted from APK)                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Note: KAORIOS_WORK_DIR is kept for module generation to pick up APK/XML/libs
# It will be cleaned up by the ModuleGenerator after use
