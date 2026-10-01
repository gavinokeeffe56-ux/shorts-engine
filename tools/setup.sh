#!/usr/bin/env bash
# One-time setup in a fresh workspace: node deps, python deps, voice model.
set -e
cd "$(dirname "$0")/.."
npm ci --silent || npm i --silent
pip install --break-system-packages -q kokoro-onnx soundfile numpy pillow
mkdir -p models
[ -f models/kokoro-v1.1.int8.onnx ] || curl -sSL -o models/kokoro-v1.1.int8.onnx https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.int8.onnx
[ -f models/voices-v1.0.bin ] || curl -sSL -o models/voices-v1.0.bin https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin
[ -f public/sfx/whoosh.wav ] || python3 tools/make_audio_assets.py
echo "setup ok"
