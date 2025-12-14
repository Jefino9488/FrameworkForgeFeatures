#@name Disable FLAG_SECURE
#@description Allows screenshots and screen recording in apps that block it
#@requires services.jar,miui-services.jar

SERVICES="$SERVICES_JAR"
MIUI_SERVICES="$MIUI_SERVICES_JAR"

if [ -z "$SERVICES" ]; then
    echo "[!] ERROR: services.jar not found"
    return 1
fi

SVC_WORK_DIR="$TMP/svc_dc"
MIUI_WORK_DIR="$TMP/miui_dc"

return_false='
    .locals 1
    const/4 v0, 0x0
    return v0
'

# ==================== SERVICES.JAR ====================
echo "[*] Decompiling services.jar..."
dynamic_apktool -decompile "$SERVICES" -o "$SVC_WORK_DIR"

if [ ! -d "$SVC_WORK_DIR" ]; then
    echo "[!] ERROR: services.jar decompilation failed"
    return 1
fi

echo "[*] Applying FLAG_SECURE patches to services.jar..."

echo "[*] Patching WindowState.isSecureLocked()..."
smali_kit -c -m "isSecureLocked" -re "$return_false" -d "$SVC_WORK_DIR" -name "WindowState.smali"

echo "[*] Patching notAllowCaptureDisplay()..."
smali_kit -c -m "notAllowCaptureDisplay" -re "$return_false" -d "$SVC_WORK_DIR" -name "WindowManagerService*.smali"

echo "[*] Patching preventTakingScreenshotToTargetWindow()..."
smali_kit -c -m "preventTakingScreenshotToTargetWindow" -re "$return_false" -d "$SVC_WORK_DIR" -name "ScreenshotController*.smali"

echo "[*] Recompiling services.jar..."
dynamic_apktool -recompile "$SVC_WORK_DIR" -o "$SERVICES"

if [ $? -ne 0 ]; then
    echo "[!] ERROR: services.jar recompilation failed"
    delete_recursive "$SVC_WORK_DIR"
    return 1
fi

delete_recursive "$SVC_WORK_DIR"

# ==================== MIUI-SERVICES.JAR ====================
if [ -n "$MIUI_SERVICES" ]; then
    echo "[*] Decompiling miui-services.jar..."
    dynamic_apktool -decompile "$MIUI_SERVICES" -o "$MIUI_WORK_DIR"

    if [ ! -d "$MIUI_WORK_DIR" ]; then
        echo "[!] WARNING: miui-services.jar decompilation failed"
    else
        echo "[*] Applying FLAG_SECURE patches to miui-services.jar..."

        echo "[*] Patching WindowManagerServiceImpl.notAllowCaptureDisplay()..."
        smali_kit -c -m "notAllowCaptureDisplay" -re "$return_false" -d "$MIUI_WORK_DIR" -name "WindowManagerServiceImpl.smali"

        echo "[*] Recompiling miui-services.jar..."
        dynamic_apktool -recompile "$MIUI_WORK_DIR" -o "$MIUI_SERVICES"
        [ $? -ne 0 ] && echo "[!] WARNING: miui-services.jar recompilation failed"

        delete_recursive "$MIUI_WORK_DIR"
    fi
else
    echo "[*] miui-services.jar not found, skipping..."
fi

echo "[*] FLAG_SECURE patch complete."
