#@name Disable FLAG_SECURE
#@description Allows screenshots and screen recording in apps that block it
#@requires services.jar,miui-services.jar

SERVICES="$SERVICES_JAR"
MIUI_SERVICES="$MIUI_SERVICES_JAR"

if [ -z "$SERVICES" ]; then
    echo "[!] ERROR: services.jar not found"
    return 1
fi

return_false='
    .locals 1
    const/4 v0, 0x0
    return v0
'

# ==================== SERVICES.JAR ====================
echo "[*] Patching services.jar..."

# Get pre-decompiled workspace (managed by run.sh)
SVC_WORK_DIR=$(get_workspace_path "services.jar")

if [ ! -d "$SVC_WORK_DIR" ]; then
    echo "[!] ERROR: services.jar workspace not found"
    return 1
fi

echo "[*] Applying FLAG_SECURE patches to services.jar..."

echo "[*] Patching WindowState.isSecureLocked()..."
smali_kit -c -m "isSecureLocked" -re "$return_false" -d "$SVC_WORK_DIR" -name "WindowState.smali"

echo "[*] Patching notAllowCaptureDisplay()..."
smali_kit -c -m "notAllowCaptureDisplay" -re "$return_false" -d "$SVC_WORK_DIR" -name "WindowManagerService*.smali"

echo "[*] Patching preventTakingScreenshotToTargetWindow()..."
smali_kit -c -m "preventTakingScreenshotToTargetWindow" -re "$return_false" -d "$SVC_WORK_DIR" -name "ScreenshotController*.smali"

echo "[+] services.jar FLAG_SECURE patches applied (recompilation handled centrally)"

# ==================== MIUI-SERVICES.JAR ====================
if [ -n "$MIUI_SERVICES" ]; then
    echo "[*] Patching miui-services.jar..."
    
    # Get pre-decompiled workspace (managed by run.sh)
    MIUI_WORK_DIR=$(get_workspace_path "miui-services.jar")

    if [ ! -d "$MIUI_WORK_DIR" ]; then
        echo "[!] WARNING: miui-services.jar workspace not found, skipping..."
    else
        echo "[*] Applying FLAG_SECURE patches to miui-services.jar..."

        echo "[*] Patching WindowManagerServiceImpl.notAllowCaptureDisplay()..."
        smali_kit -c -m "notAllowCaptureDisplay" -re "$return_false" -d "$MIUI_WORK_DIR" -name "WindowManagerServiceImpl.smali"

        echo "[+] miui-services.jar FLAG_SECURE patches applied (recompilation handled centrally)"
    fi
else
    echo "[*] miui-services.jar not found, skipping..."
fi

echo "[*] FLAG_SECURE patch complete."
