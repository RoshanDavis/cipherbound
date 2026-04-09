# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec file for Cipherbound Vision Server.
Builds a single standalone Windows executable.

Usage:
  1. Activate venv:  .\venv\Scripts\activate
  2. Install pyinstaller:  pip install pyinstaller
  3. Build:  pyinstaller --clean cipherbound_vision.spec
"""

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

# MediaPipe ships model files and other data that must be bundled
mediapipe_datas = collect_data_files('mediapipe')
mediapipe_hiddenimports = collect_submodules('mediapipe')

block_cipher = None

a = Analysis(
    ['src/main.py'],
    pathex=['src'],
    binaries=[],
    datas=mediapipe_datas,
    hiddenimports=[
        # Our own modules
        'config',
        'network',
        'trackers',
        'trackers.look',
        'trackers.strafe',
        'trackers.depth',
        'trackers.hands',
        'trackers.base',
        'trackers.gestures',
        'trackers.cipher_templates',
        'trackers.shape_recognizer',
        # Dependencies that PyInstaller may miss
        'cv2',
        'numpy',
        'mediapipe',
        'google.protobuf',
        'google.protobuf.descriptor',
        'sounddevice',
        'json',
        'socket',
    ] + mediapipe_hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='CipherboundVision',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
