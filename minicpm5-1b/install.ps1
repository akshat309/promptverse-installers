<#
.SYNOPSIS
PromptVerse One-Click Automated Installer for MiniCPM5-1B
.DESCRIPTION
Installs Python/Git, creates a venv, validates hardware, clones the MiniCPM repository, 
downloads model weights persistently via Git LFS, and launches a Light-Themed LM Studio-style WebUI.
#>

$ErrorActionPreference = "Stop"
$InstallPath = "C:\MiniCPM5-1B"
$RepoUrl = "https://github.com/OpenBMB/MiniCPM.git"
$ModelUrl = "https://huggingface.co/openbmb/MiniCPM5-1B"
$ShortcutPath = "$([Environment]::GetFolderPath('Desktop'))\MiniCPM5-1B PromptVerse.lnk"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   PROMPTVERSE: MINICPM5-1B ONE-CLICK INSTALLER       " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Cyan

# 1. System Validation (RAM & VRAM)
Write-Host "`n[1/8] Running System Validation..." -ForegroundColor Yellow
$TotalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Write-Host "System RAM: ${TotalRAM}GB detected."
if ($TotalRAM -lt 8) { Write-Host "WARNING: 8GB+ RAM recommended for smooth operation." -ForegroundColor Red }

$CudaVersion = "cpu"
$TorchCmd = "pip install torch torchvision torchaudio"
try {
    $NvidiaSmi = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    if ($NvidiaSmi) {
        $VRAM = [math]::Round([int]$NvidiaSmi / 1024)
        Write-Host "GPU VRAM: ${VRAM}GB detected."
        
        $CudaCheck = & nvidia-smi 2>$null | Select-String "CUDA Version: (\d+\.\d+)"
        if ($CudaCheck) {
            $Version = $CudaCheck.Matches.Groups[1].Value
            if ([decimal]$Version -ge 12.1) { $CudaVersion = "cu121"; $TorchCmd = "pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121" }
            elseif ([decimal]$Version -ge 11.8) { $CudaVersion = "cu118"; $TorchCmd = "pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118" }
        }
        Write-Host "Configured for PyTorch backend: $CudaVersion"
    }
} catch {
    Write-Host "No NVIDIA GPU detected. Defaulting to CPU setup." -ForegroundColor Yellow
}

# 2. Environment Check (Python & Git)
Write-Host "`n[2/8] Checking Git & Python..." -ForegroundColor Yellow
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via Winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found. Installing Python 3.10 via Winget..."
    winget install --id Python.Python.3.10 -e --source winget --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# 3. Clone Base Repository
Write-Host "`n[3/8] Setting up installation directory..." -ForegroundColor Yellow
if (!(Test-Path $InstallPath)) { New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null }
Set-Location $InstallPath
if (!(Test-Path "$InstallPath\.git")) { git clone $RepoUrl . }

# 4. Clone Model Weights Permanently via Git LFS
Write-Host "`n[4/8] Initializing Git LFS and Downloading Model Weights (This happens only once)..." -ForegroundColor Yellow
& git lfs install
$ModelPath = "$InstallPath\model_weights"
if (!(Test-Path $ModelPath)) {
    & git clone $ModelUrl $ModelPath
} else {
    Write-Host "Model weights already found locally. Skipping download." -ForegroundColor Green
}

# 5. Virtual Environment Setup
Write-Host "`n[5/8] Creating Python Virtual Environment..." -ForegroundColor Yellow
if (!(Test-Path "$InstallPath\venv")) { python -m venv venv }
$ActivateCmd = "$InstallPath\venv\Scripts\activate.ps1"

# 6. Installing Dependencies
Write-Host "`n[6/8] Installing PyTorch & Dependencies (This may take a while)..." -ForegroundColor Yellow
& "$InstallPath\venv\Scripts\python.exe" -m pip install --upgrade pip
Invoke-Expression "& '$InstallPath\venv\Scripts\python.exe' -m $TorchCmd"

$ReqContent = @"
transformers>=5.6
accelerate
gradio
huggingface_hub
bitsandbytes
"@
Set-Content -Path "$InstallPath\requirements_webui.txt" -Value $ReqContent
& "$InstallPath\venv\Scripts\python.exe" -m pip install -r "$InstallPath\requirements_webui.txt"

# 7. Generate PromptVerse LM-Studio Style WebUI
Write-Host "`n[7/8] Generating PromptVerse Gradio UI..." -ForegroundColor Yellow
$AppContent = @"
import os
import gradio as gr
from transformers import AutoModelForCausalLM, AutoTokenizer, TextIteratorStreamer
import torch
from threading import Thread

# Force Light Mode for LM Studio feel
os.environ["GRADIO_THEME"] = "light"

model_path = './model_weights'
print(f'Loading MiniCPM5-1B locally from {model_path}...')

tokenizer = AutoTokenizer.from_pretrained(model_path)
model = AutoModelForCausalLM.from_pretrained(
    model_path,
    torch_dtype='auto',
    device_map='auto'
)

def generate_chat(message, history, think_mode):
    messages = []
    for user_msg, bot_msg in history:
        messages.append({"role": "user", "content": user_msg})
        messages.append({"role": "assistant", "content": bot_msg})
    
    messages.append({"role": "user", "content": message})
    
    inputs = tokenizer.apply_chat_template(
        messages,
        tokenize=True,
        add_generation_prompt=True,
        enable_thinking=think_mode,
        return_dict=True,
        return_tensors='pt'
    ).to(model.device)
    
    streamer = TextIteratorStreamer(tokenizer, timeout=10.0, skip_prompt=True, skip_special_tokens=True)
    
    generate_kwargs = dict(
        **inputs,
        streamer=streamer,
        max_new_tokens=1024,
        temperature=0.7 if not think_mode else 0.9,
        top_p=0.95
    )
    
    t = Thread(target=model.generate, kwargs=generate_kwargs)
    t.start()
    
    partial_message = ""
    for new_text in streamer:
        partial_message += new_text
        yield partial_message

# Clean, monochrome theme mimicking native desktop apps
custom_theme = gr.themes.Monochrome(
    primary_hue="zinc",
    secondary_hue="zinc",
    neutral_hue="zinc",
    font=[gr.themes.GoogleFont("Inter"), "ui-sans-serif", "system-ui", "sans-serif"]
)

with gr.Blocks(theme=custom_theme, title='PromptVerse MiniCPM5-1B') as demo:
    with gr.Row():
        with gr.Column(scale=1, min_width=300):
            gr.Markdown("<h2 style='color: #111;'>🌌 PromptVerse</h2>")
            gr.Markdown("**Model:** MiniCPM5-1B<br>**Status:** Loaded Locally (Offline)")
            gr.Divider()
            gr.Markdown("### ⚙️ Inference Settings")
            think_toggle = gr.Checkbox(label='Enable <think> Reasoning Mode', value=True)
            gr.Markdown("*When enabled, the model acts as a deliberate reasoner. Disable for faster, general chat.*")
            
        with gr.Column(scale=4):
            gr.ChatInterface(
                fn=generate_chat,
                additional_inputs=[think_toggle],
                chatbot=gr.Chatbot(height=650, show_copy_button=True, render_markdown=True),
                textbox=gr.Textbox(placeholder="Send a message to MiniCPM5...", container=False, scale=7),
                theme="light"
            )

if __name__ == '__main__':
    demo.launch(inbrowser=True)
"@
Set-Content -Path "$InstallPath\promptverse_app.py" -Value $AppContent

$BatContent = @"
@echo off
title PromptVerse MiniCPM5-1B Launcher
cd /d $InstallPath
call venv\Scripts\activate.bat
echo Starting PromptVerse WebUI...
python promptverse_app.py
pause
"@
Set-Content -Path "$InstallPath\start_webui.bat" -Value $BatContent

# 8. Desktop Shortcut & Cleanup
Write-Host "`n[8/8] Creating Desktop Shortcut..." -ForegroundColor Yellow
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "$InstallPath\start_webui.bat"
$Shortcut.WorkingDirectory = $InstallPath
$Shortcut.IconLocation = "cmd.exe"
$Shortcut.Save()

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host " INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host " The model is saved locally. A shortcut is on your Desktop."
Write-Host "======================================================" -ForegroundColor Cyan
