#@name Kaorios Toolbox
#@description Enables Play Integrity fix, Pixel spoofing, and unlimited Google Photos backup via Kaorios Toolbox framework patches
#@requires framework.jar

# ==================== MODULE CONFIGURATION ====================
echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Kaorios Toolbox Framework Patcher            ║"
echo "║   Play Integrity | Pixel Spoofing | GPhotos    ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

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

# ==================== STEP 1: DOWNLOAD COMPONENTS ====================
echo "[*] Step 1: Downloading Kaorios Toolbox components..."

download_kaorios_components() {
    echo "[*] Fetching Kaorios Toolbox release information..."
    mkdir -p "$KAORIOS_WORK_DIR" "$UTILS_DIR"
    
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
        echo "[!] ERROR: Failed to fetch release information"
        return 1
    fi
    
    local version=$(grep -o '"tag_name": *"[^"]*"' "$release_info" | head -1 | sed 's/"tag_name": *"\(.*\)"/\1/')
    echo "[*] Latest version: $version"
    
    local apk_url=$(grep -o '"browser_download_url": *"[^"]*KaoriosToolbox[^"]*\.apk"' "$release_info" | head -1 | sed 's/"browser_download_url": *"\(.*\)"/\1/')
    local xml_url=$(grep -o '"browser_download_url": *"[^"]*privapp_whitelist[^"]*\.xml"' "$release_info" | head -1 | sed 's/"browser_download_url": *"\(.*\)"/\1/')
    local dex_url=$(grep -o '"browser_download_url": *"[^"]*classes[^"]*\.dex"' "$release_info" | head -1 | sed 's/"browser_download_url": *"\(.*\)"/\1/')
    
    if [ -z "$apk_url" ] || [ -z "$xml_url" ] || [ -z "$dex_url" ]; then
        echo "[!] ERROR: Could not find required assets in release"
        return 1
    fi
    
    echo "[*] Assets found:"
    echo "    APK: $(basename "$apk_url")"
    echo "    XML: $(basename "$xml_url")"
    echo "    DEX: $(basename "$dex_url")"
    
    echo "[*] Downloading KaoriosToolbox.apk..."
    if command -v curl >/dev/null 2>&1; then
        curl -sL -o "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "$apk_url"
    else
        wget -q -O "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "$apk_url"
    fi
    
    echo "[*] Downloading permission XML..."
    if command -v curl >/dev/null 2>&1; then
        curl -sL -o "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" "$xml_url"
    else
        wget -q -O "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" "$xml_url"
    fi
    
    echo "[*] Downloading classes.dex..."
    if command -v curl >/dev/null 2>&1; then
        curl -sL -o "$KAORIOS_WORK_DIR/classes.dex" "$dex_url"
    else
        wget -q -O "$KAORIOS_WORK_DIR/classes.dex" "$dex_url"
    fi
    
    echo "[+] All Kaorios components downloaded successfully"
    return 0
}

download_kaorios_components || return 1

# ==================== STEP 2: EXTRACT UTILITY CLASSES ====================
echo ""
echo "[*] Step 2: Extracting utility classes from classes.dex..."

extract_utility_classes() {
    echo "[*] Extracting Kaorios utility classes from classes.dex..."
    mkdir -p "$DEX_EXTRACT_DIR/smali"
    
    local dex_path="$KAORIOS_WORK_DIR/classes.dex"
    local baksmali_jar=""
    for jar in "$l/baksmali.jar" "$DI_BIN/baksmali.jar" /data/tmp/di/bin/baksmali.jar; do
        if [ -f "$jar" ]; then
            baksmali_jar="$jar"
            echo "[*] Found baksmali: $baksmali_jar"
            break
        fi
    done
    
    if [ -z "$baksmali_jar" ]; then
        echo "[!] ERROR: baksmali.jar not found"
        return 1
    fi
    
    echo "[*] Decompiling classes.dex using baksmali..."
    if run_jar "$baksmali_jar" d "$dex_path" -o "$DEX_EXTRACT_DIR/smali"; then
        echo "[+] baksmali completed successfully"
    else
        echo "[!] ERROR: baksmali failed"
        return 1
    fi
    
    local utils_source=$(find "$DEX_EXTRACT_DIR" -type d -path "*/com/android/internal/util/kaorios" 2>/dev/null | head -1)
    if [ -z "$utils_source" ] || [ ! -d "$utils_source" ]; then
        echo "[!] ERROR: Could not find kaorios utility classes"
        return 1
    fi
    
    cp -r "$utils_source" "$UTILS_DIR/"
    local class_count=$(find "$UTILS_DIR/kaorios" -name "*.smali" 2>/dev/null | wc -l)
    echo "[+] Extracted $class_count utility classes from classes.dex"
    return 0
}

extract_utility_classes || return 1

# ==================== STEP 3: DECOMPILE FRAMEWORK.JAR ====================
echo ""
echo "[*] Step 3: Decompiling framework.jar..."

mkdir -p "$FW_WORK_DIR"
dynamic_apktool -d "$FRAMEWORK" -o "$FW_WORK_DIR" || { echo "[!] ERROR: Decompilation failed"; return 1; }

# ==================== STEP 4: INJECT UTILITY CLASSES ====================
echo ""
echo "[*] Step 4: Injecting Kaorios utility classes..."

inject_utility_classes() {
    local decompile_dir="$1"
    echo "[*] Injecting Kaorios utility classes into framework..."
    local target_smali_dir=$(get_last_smali_dir "$decompile_dir")
    echo "[*] Injecting into $target_smali_dir"
    local target_dir="$decompile_dir/$target_smali_dir/com/android/internal/util/kaorios"
    mkdir -p "$target_dir"
    cp -r "$UTILS_DIR/kaorios"/* "$target_dir/"
    local copied_count=$(find "$target_dir" -name "*.smali" | wc -l)
    echo "[+] Injected $copied_count Kaorios utility classes"
    return 0
}

inject_utility_classes "$FW_WORK_DIR" || return 1

# ==================== STEP 5: APPLY PATCHES ====================
echo ""
echo "[*] Step 5: Applying Kaorios framework patches..."

# Patch ApplicationPackageManager
patch_apm() {
    echo "[*] Patching ApplicationPackageManager.hasSystemFeature..."
    
    local target_file=$(find "$FW_WORK_DIR" -type f -path "*/android/app/ApplicationPackageManager.smali" | head -1)
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: ApplicationPackageManager.smali not found"
        return 0
    fi
    
    # Relocate to last smali dir (following kaorios_patches.sh approach)
    local current_smali_dir=$(echo "$target_file" | sed -E 's|(.*/smali(_classes[0-9]*)?)/.*|\1|')
    local last_smali_dir=$(get_last_smali_dir "$FW_WORK_DIR")
    local target_root="$FW_WORK_DIR/$last_smali_dir"
    
    if [ "$current_smali_dir" != "$target_root" ]; then
        echo "[*] Relocating ApplicationPackageManager to $last_smali_dir..."
        
        # Create destination directory
        local new_dir="$target_root/android/app"
        mkdir -p "$new_dir"
        
        # Move main class and all inner classes
        local src_dir=$(dirname "$target_file")
        local file_count=$(ls -1 "$src_dir"/ApplicationPackageManager*.smali 2>/dev/null | wc -l)
        mv "$src_dir"/ApplicationPackageManager*.smali "$new_dir/" 2>/dev/null
        
        target_file="$new_dir/ApplicationPackageManager.smali"
        echo "[+] Relocated ApplicationPackageManager and $file_count inner class files to $last_smali_dir"
    fi
    
    # Check if already patched
    if grep -q "Lcom/android/internal/util/kaorios/KaoriFeaturesUtils" "$target_file"; then
        echo "[*] ApplicationPackageManager already patched"
        return 0
    fi
    
    # Step 1: Add mContext field for Context type (not ContextImpl) after instance fields comment
    if ! grep -q "\.field private final mContext:Landroid/content/Context;" "$target_file"; then
        local insert_line=$(grep -n "^# instance fields" "$target_file" | head -1 | cut -d: -f1)
        if [ -n "$insert_line" ]; then
            head -n "$insert_line" "$target_file" > "${target_file}.tmp"
            echo ".field private final mContext:Landroid/content/Context;" >> "${target_file}.tmp"
            echo "" >> "${target_file}.tmp"
            tail -n +$((insert_line + 1)) "$target_file" >> "${target_file}.tmp"
            mv "${target_file}.tmp" "$target_file"
            echo "[+] Added mContext field"
        fi
    fi
    
    # Step 2: Add constructor for Context (not ContextImpl)
    if ! grep -q "\.method public constructor <init>(Landroid/content/Context;)V" "$target_file"; then
        local first_method_line=$(grep -n "^\.method" "$target_file" | head -1 | cut -d: -f1)
        if [ -n "$first_method_line" ]; then
            head -n $((first_method_line - 1)) "$target_file" > "${target_file}.tmp"
            cat >> "${target_file}.tmp" << 'CONSTRUCTOR'

.method public constructor <init>(Landroid/content/Context;)V
    .registers 2

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Landroid/app/ApplicationPackageManager;->mContext:Landroid/content/Context;

    return-void
.end method

CONSTRUCTOR
            tail -n +$first_method_line "$target_file" >> "${target_file}.tmp"
            mv "${target_file}.tmp" "$target_file"
            echo "[+] Added ApplicationPackageManager(Context) constructor"
        fi
    fi
    
    # Step 3: Find hasSystemFeature method and patch it
    # We need to find the method, change .locals/.registers to .registers 12, and insert Kaorios block before sget-object mHasSystemFeatureCache
    
    # Find line number of "hasSystemFeature(Ljava/lang/String;I)Z"
    local method_start=$(grep -n "\.method.*hasSystemFeature(Ljava/lang/String;I)Z" "$target_file" | head -1 | cut -d: -f1)
    
    if [ -n "$method_start" ]; then
        echo "[*] Found hasSystemFeature method at line $method_start"
        
        # Find the .registers OR .locals line in this method (first few lines after method start)
        # Use grep -E for extended regex to support | (OR) pattern
        local reg_rel_line=$(tail -n +$method_start "$target_file" | head -n 10 | grep -E -n '\.registers|\.locals' | head -1 | cut -d: -f1)
        if [ -n "$reg_rel_line" ]; then
            local actual_reg_line=$((method_start + reg_rel_line - 1))
            # Replace .registers X or .locals X with .registers 12
            sed -i "${actual_reg_line}s/\.registers [0-9]*/.registers 12/" "$target_file"
            sed -i "${actual_reg_line}s/\.locals [0-9]*/.registers 12/" "$target_file"
            echo "[+] Changed .locals/.registers to .registers 12 in hasSystemFeature (line $actual_reg_line)"
        else
            echo "[!] WARNING: Could not find .registers/.locals in hasSystemFeature"
        fi
        
        # Find the sget-object mHasSystemFeatureCache line (relative to method start)
        local cache_rel_line=$(tail -n +$method_start "$target_file" | grep -n "sget-object.*mHasSystemFeatureCache" | head -1 | cut -d: -f1)
        if [ -n "$cache_rel_line" ]; then
            local insert_at=$((method_start + cache_rel_line - 1))
            
            # Create the Kaorios block file
            local block_file="$TMP/kaorios_apm_block.smali"
            cat > "$block_file" << 'KBLOCK'

    # Kaorios Toolbox - Feature spoofing
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

    if-eqz v0, :cond_kaorios_passthrough

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackageGsa()Ljava/lang/String;

    move-result-object v5

    invoke-virtual {v0, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v5

    if-nez v5, :cond_kaorios_dospoofcheck

    invoke-static {}, Lcom/android/internal/util/kaorios/KaoriFeaturesUtils;->getPackagePhotos()Ljava/lang/String;

    move-result-object v5

    invoke-virtual {v0, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v5

    if-eqz v5, :cond_kaorios_passthrough

    :cond_kaorios_dospoofcheck
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v5

    invoke-interface {v5, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v5

    if-nez v5, :cond_kaorios_rettrue

    invoke-static {v4}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v5

    invoke-interface {v5, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z

    move-result v5

    if-nez v5, :cond_kaorios_rettrue

    goto :cond_kaorios_passthrough

    :cond_kaorios_rettrue
    return v3

    :cond_kaorios_passthrough

KBLOCK
            # Insert block before the cache line
            head -n $((insert_at - 1)) "$target_file" > "${target_file}.tmp"
            cat "$block_file" >> "${target_file}.tmp"
            tail -n +$insert_at "$target_file" >> "${target_file}.tmp"
            mv "${target_file}.tmp" "$target_file"
            rm -f "$block_file"
            echo "[+] Inserted Kaorios logic block in hasSystemFeature"
        fi
    fi
    
    echo "[+] Patched ApplicationPackageManager"
    return 0
}

# Patch Instrumentation
patch_instrumentation() {
    echo "[*] Patching Instrumentation.newApplication methods..."
    
    local target_file=$(find "$FW_WORK_DIR" -type f -path "*/android/app/Instrumentation.smali" | head -1)
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: Instrumentation.smali not found"
        return 0
    fi
    
    if grep -q "ToolboxUtils;->KaoriosProps" "$target_file"; then
        echo "[*] Already patched"
        return 0
    fi
    
    # Patch static newApplication(Class, Context) - p1 is context
    # Find "return-object v0" after ".method public static whitelist newApplication(Ljava/lang/Class;Landroid/content/Context;)"
    local method1_start=$(grep -n "\.method.*static.*newApplication(Ljava/lang/Class;Landroid/content/Context;)" "$target_file" | head -1 | cut -d: -f1)
    if [ -n "$method1_start" ]; then
        local method1_end=$(tail -n +$method1_start "$target_file" | grep -n "^\.end method" | head -1 | cut -d: -f1)
        if [ -n "$method1_end" ]; then
            local return_rel=$(tail -n +$method1_start "$target_file" | head -n $method1_end | grep -n "return-object v0" | tail -1 | cut -d: -f1)
            if [ -n "$return_rel" ]; then
                local insert_at=$((method1_start + return_rel - 1))
                head -n $((insert_at - 1)) "$target_file" > "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                echo "    invoke-static {p1}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosProps(Landroid/content/Context;)V" >> "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                tail -n +$insert_at "$target_file" >> "${target_file}.tmp"
                mv "${target_file}.tmp" "$target_file"
                echo "[+] Patched static newApplication(Class, Context)"
            fi
        fi
    fi
    
    # Patch instance newApplication(ClassLoader, String, Context) - p3 is context
    # Re-read file since we modified it
    local method2_start=$(grep -n "\.method.*newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)" "$target_file" | head -1 | cut -d: -f1)
    if [ -n "$method2_start" ]; then
        local method2_end=$(tail -n +$method2_start "$target_file" | grep -n "^\.end method" | head -1 | cut -d: -f1)
        if [ -n "$method2_end" ]; then
            local return_rel=$(tail -n +$method2_start "$target_file" | head -n $method2_end | grep -n "return-object v0" | tail -1 | cut -d: -f1)
            if [ -n "$return_rel" ]; then
                local insert_at=$((method2_start + return_rel - 1))
                head -n $((insert_at - 1)) "$target_file" > "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                echo "    invoke-static {p3}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosProps(Landroid/content/Context;)V" >> "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                tail -n +$insert_at "$target_file" >> "${target_file}.tmp"
                mv "${target_file}.tmp" "$target_file"
                echo "[+] Patched instance newApplication(ClassLoader, String, Context)"
            fi
        fi
    fi
    
    echo "[+] Patched Instrumentation"
    return 0
}

# Patch KeyStore2
patch_keystore2() {
    echo "[*] Patching KeyStore2.getKeyEntry..."
    
    local target_file=$(find "$FW_WORK_DIR" -type f -path "*/android/security/KeyStore2.smali" | head -1)
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: KeyStore2.smali not found"
        return 0
    fi
    
    if grep -q "ToolboxUtils;->KaoriosKeybox" "$target_file"; then
        echo "[*] Already patched"
        return 0
    fi
    
    # Find getKeyEntry method and its return-object v0
    local method_start=$(grep -n "\.method.*getKeyEntry(Landroid/system/keystore2/KeyDescriptor;)" "$target_file" | head -1 | cut -d: -f1)
    if [ -n "$method_start" ]; then
        local method_end=$(tail -n +$method_start "$target_file" | grep -n "^\.end method" | head -1 | cut -d: -f1)
        if [ -n "$method_end" ]; then
            local return_rel=$(tail -n +$method_start "$target_file" | head -n $method_end | grep -n "return-object v0" | tail -1 | cut -d: -f1)
            if [ -n "$return_rel" ]; then
                local insert_at=$((method_start + return_rel - 1))
                head -n $((insert_at - 1)) "$target_file" > "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                echo "    invoke-static {v0}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosKeybox(Landroid/system/keystore2/KeyEntryResponse;)Landroid/system/keystore2/KeyEntryResponse;" >> "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                echo "    move-result-object v0" >> "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                tail -n +$insert_at "$target_file" >> "${target_file}.tmp"
                mv "${target_file}.tmp" "$target_file"
                echo "[+] Patched KeyStore2.getKeyEntry"
            fi
        fi
    fi
    
    return 0
}

# Patch AndroidKeyStoreSpi
patch_keystore_spi() {
    echo "[*] Patching AndroidKeyStoreSpi.engineGetCertificateChain..."
    
    local target_file=$(find "$FW_WORK_DIR" -type f -path "*/android/security/keystore2/AndroidKeyStoreSpi.smali" | head -1)
    if [ -z "$target_file" ]; then
        echo "[!] WARNING: AndroidKeyStoreSpi.smali not found"
        return 0
    fi
    
    if grep -q "ToolboxUtils;->KaoriosPropsEngineGetCertificateChain" "$target_file"; then
        echo "[*] Already patched"
        return 0
    fi
    
    # Find engineGetCertificateChain method (may have test-api annotation)
    local method_start=$(grep -n "\.method.*engineGetCertificateChain" "$target_file" | head -1 | cut -d: -f1)
    if [ -n "$method_start" ]; then
        echo "[*] Found engineGetCertificateChain at line $method_start"
        
        # Patch 1: Insert after .registers or .locals line (search first 20 lines)
        # Use grep -E for extended regex to support | (OR) pattern
        local registers_rel=$(tail -n +$method_start "$target_file" | head -n 20 | grep -E -n '\.registers|\.locals' | head -1 | cut -d: -f1)
        if [ -n "$registers_rel" ]; then
            local insert_at=$((method_start + registers_rel))
            echo "[*] Inserting after registers at line $insert_at"
            head -n $insert_at "$target_file" > "${target_file}.tmp"
            echo "" >> "${target_file}.tmp"
            echo "    invoke-static {}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosPropsEngineGetCertificateChain()V" >> "${target_file}.tmp"
            echo "" >> "${target_file}.tmp"
            tail -n +$((insert_at + 1)) "$target_file" >> "${target_file}.tmp"
            mv "${target_file}.tmp" "$target_file"
            echo "[+] Added KaoriosPropsEngineGetCertificateChain call"
        else
            echo "[!] WARNING: Could not find .registers/.locals in engineGetCertificateChain"
        fi
        
        # Patch 2: Insert before return-object v3 (re-find method since file changed)
        method_start=$(grep -n "\.method.*engineGetCertificateChain" "$target_file" | head -1 | cut -d: -f1)
        local method_end=$(tail -n +$method_start "$target_file" | grep -n "^\.end method" | head -1 | cut -d: -f1)
        if [ -n "$method_end" ]; then
            local return_rel=$(tail -n +$method_start "$target_file" | head -n $method_end | grep -n "return-object v3" | head -1 | cut -d: -f1)
            if [ -n "$return_rel" ]; then
                local insert_at=$((method_start + return_rel - 1))
                head -n $((insert_at - 1)) "$target_file" > "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                echo "    invoke-static {v3}, Lcom/android/internal/util/kaorios/ToolboxUtils;->KaoriosKeybox([Ljava/security/cert/Certificate;)[Ljava/security/cert/Certificate;" >> "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                echo "    move-result-object v3" >> "${target_file}.tmp"
                echo "" >> "${target_file}.tmp"
                tail -n +$insert_at "$target_file" >> "${target_file}.tmp"
                mv "${target_file}.tmp" "$target_file"
                echo "[+] Added KaoriosKeybox call before return"
            fi
        fi
    else
        echo "[!] WARNING: engineGetCertificateChain method not found"
    fi
    
    echo "[+] Patched AndroidKeyStoreSpi"
    return 0
}

# Apply all patches
patch_apm
patch_instrumentation
patch_keystore2
patch_keystore_spi

# ==================== STEP 6: RECOMPILE ====================
echo ""
echo "[*] Step 6: Recompiling framework.jar..."

# OOM mitigation: Free memory before recompilation
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

# Use -j 2 to limit threads and prevent OOM during recompilation of large framework.jar
# dynamic_apktool passes unrecognized flags to apktool
# Output directly to $FRAMEWORK (DI convention - modifies input file in place)
dynamic_apktool -r "$FW_WORK_DIR" -o "$FRAMEWORK" -j 2

if [ ! -f "$FRAMEWORK" ]; then
    echo "[!] ERROR: framework.jar recompilation failed"
    return 1
fi

echo "[+] Kaorios Toolbox patches applied successfully!"

# ==================== STEP 7: REGISTER MODULE EXTRAS ====================
echo ""
echo "[*] Step 7: Registering module extras..."

if [ -f "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" ]; then
    add_to_module "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "system/system_ext/priv-app/KaoriosToolbox/KaoriosToolbox.apk" "apk"
    
    mkdir -p "$TMP/apk_extract"
    unzip -q "$KAORIOS_WORK_DIR/KaoriosToolbox.apk" "lib/*" -d "$TMP/apk_extract" 2>/dev/null
    
    for arch in arm64-v8a armeabi-v7a x86 x86_64; do
        arch_short=$(echo "$arch" | sed 's/arm64-v8a/arm64/;s/armeabi-v7a/arm/;s/x86_64/x86_64/;s/x86$/x86/')
        if [ -d "$TMP/apk_extract/lib/$arch" ]; then
            for lib in "$TMP/apk_extract/lib/$arch"/*.so; do
                if [ -f "$lib" ]; then
                    libname=$(basename "$lib")
                    add_to_module "$lib" "system/system_ext/priv-app/KaoriosToolbox/lib/$arch_short/$libname" "lib"
                fi
            done
        fi
    done
    echo "[+] Native libraries extracted and registered"
fi

if [ -f "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" ]; then
    add_to_module "$KAORIOS_WORK_DIR/privapp_whitelist_com.kousei.kaorios.xml" "system/system_ext/etc/permissions/privapp_whitelist_com.kousei.kaorios.xml" "xml"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Kaorios Toolbox patches applied successfully!             ║"
echo "║                                                                ║"
echo "║   ✓ ApplicationPackageManager.hasSystemFeature                 ║"
echo "║   ✓ Instrumentation.newApplication (both variants)             ║"
echo "║   ✓ KeyStore2.getKeyEntry                                      ║"
echo "║   ✓ AndroidKeyStoreSpi.engineGetCertificateChain               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
