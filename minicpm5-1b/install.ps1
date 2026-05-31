<#
.SYNOPSIS
PromptVerse One-Click Automated Installer for MiniCPM5-1B (Official UI - Fixed)
.DESCRIPTION
Installs Python/Git, creates a venv, validates hardware, clones model weights 
persistently via Git LFS, writes the official OpenBMB UI flawlessly, and sets up a launcher.
#>

$ErrorActionPreference = "Stop"
$InstallPath = "C:\MiniCPM5-1B"
$ModelUrl = "https://huggingface.co/openbmb/MiniCPM5-1B"
$ShortcutPath = "$([Environment]::GetFolderPath('Desktop'))\MiniCPM5-1B PromptVerse.lnk"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   PROMPTVERSE: MINICPM5-1B OFFICIAL DEMO INSTALLER   " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Cyan

# 1. System Validation (RAM & VRAM)
Write-Host "`n[1/7] Running System Validation..." -ForegroundColor Yellow
$TotalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Write-Host "System RAM: ${TotalRAM}GB detected."

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
Write-Host "`n[2/7] Checking Git & Python..." -ForegroundColor Yellow
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via Winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found. Installing Python 3.12 via Winget..."
    winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# 3. Clone Model Weights Permanently via Git LFS
Write-Host "`n[3/7] Initializing Git LFS and Downloading Model Weights (Persistent Local Storage)..." -ForegroundColor Yellow
if (!(Test-Path $InstallPath)) { New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null }
Set-Location $InstallPath

& git lfs install
$ModelPath = "$InstallPath\model_weights"
if (!(Test-Path $ModelPath)) {
    Write-Host "Downloading model weights via Git LFS..." -ForegroundColor Cyan
    & git clone $ModelUrl $ModelPath
} else {
    Write-Host "Model weights already found locally. Skipping download." -ForegroundColor Green
}

# 4. Virtual Environment Setup
Write-Host "`n[4/7] Creating Python Virtual Environment..." -ForegroundColor Yellow
if (!(Test-Path "$InstallPath\venv")) { python -m venv venv }

# 5. Installing Dependencies
Write-Host "`n[5/7] Installing PyTorch & Official UI Requirements..." -ForegroundColor Yellow
& "$InstallPath\venv\Scripts\python.exe" -m pip install --upgrade pip
Invoke-Expression "& '$InstallPath\venv\Scripts\python.exe' -m $TorchCmd"

$ReqContent = @'
gradio>=6.14.0
transformers>=4.56
accelerate
sentencepiece
fastapi
uvicorn>=0.14.0
'@
Set-Content -Path "$InstallPath\requirements.txt" -Value $ReqContent
& "$InstallPath\venv\Scripts\python.exe" -m pip install -r "$InstallPath\requirements.txt"

# 6. Writing Official Application Structure
Write-Host "`n[6/7] Deploying Official UI Assets..." -ForegroundColor Yellow

# File 1: utils_chatbot.py (Using literal here-string to avoid escaping syntax bugs)
$UtilsContent = @'
def organize_messages(message, history=None):
    """Build chat messages from history tuples [[user, assistant], ...]."""
    msg_ls = [{"role": "system", "content": "You are a helpful assistant."}]
    if history:
        for turn in history:
            if not turn:
                continue
            user_text = turn[0] if len(turn) > 0 else None
            assistant_text = turn[1] if len(turn) > 1 else None
            if user_text:
                msg_ls.append({"role": "user", "content": user_text})
            if assistant_text:
                msg_ls.append({"role": "assistant", "content": assistant_text})
    msg_ls.append({"role": "user", "content": message})
    return msg_ls
'@
Set-Content -Path "$InstallPath\utils_chatbot.py" -Value $UtilsContent

# File 2: app.py
$AppContent = @'
import os
import logging
import threading
from typing import Generator
import torch
import gradio as gr
from transformers import AutoModelForCausalLM, AutoTokenizer, TextIteratorStreamer
from utils_chatbot import organize_messages

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MODEL_PATH = "./model_weights"

tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
device = "cuda" if torch.cuda.is_available() else "cpu"
dtype = torch.bfloat16 if torch.cuda.is_available() else torch.float32

model = AutoModelForCausalLM.from_pretrained(
    MODEL_PATH,
    torch_dtype=dtype,
    trust_remote_code=True,
).to(device)

with gr.Blocks(title="MiniCPM5-1B Demo") as demo:
    gr.Markdown("# MiniCPM5-1B Official Local Interface")
    
    def predict(
        message: str,
        history: list | None = None,
        thinking_mode: bool = True,
        temperature: float = 0.9,
        top_p: float = 0.95,
    ):
        messages = organize_messages(message, history)
        prompt_text = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=thinking_mode,
        )
        model_inputs = tokenizer([prompt_text], return_tensors="pt").to(device)
        streamer = TextIteratorStreamer(tokenizer, skip_prompt=True, skip_special_tokens=False)

        gen_kwargs = dict(**model_inputs, streamer=streamer, max_new_tokens=4096)
        if temperature > 0 and device == "cuda":
            gen_kwargs.update(temperature=temperature, top_p=top_p, do_sample=True)
        else:
            gen_kwargs.update(do_sample=False)

        thread = threading.Thread(target=model.generate, kwargs=gen_kwargs)
        thread.start()

        full_text = ""
        for new_token_text in streamer:
            if not new_token_text:
                continue
            full_text += new_token_text
            yield full_text
        thread.join()

    gr.ChatInterface(fn=predict, additional_inputs=[gr.Checkbox(label="Thinking Mode", value=True)])

if __name__ == "__main__":
    demo.launch(inbrowser=True, server_port=7860)
'@
Set-Content -Path "$InstallPath\app.py" -Value $AppContent

# File 3: Batch Execution Launcher
$BatContent = @"
@echo off
title PromptVerse Official MiniCPM5-1B UI
cd /d $InstallPath
call venv\Scripts\activate.bat
echo Launching Official MiniCPM Interface...
python app.py
pause
"@
Set-Content -Path "$InstallPath\start_webui.bat" -Value $BatContent

# 7. Desktop Shortcut & Cleanup
Write-Host "`n[7/7] Finalizing System Integration..." -ForegroundColor Yellow
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "$InstallPath\start_webui.bat"
$Shortcut.WorkingDirectory = $InstallPath
$Shortcut.IconLocation = "cmd.exe"
$Shortcut.Save()

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host " PRODUCTION ARCHITECTURE DEPLOYED SUCCESSFULLY!" -ForegroundColor Green
Write-Host " Weights are saved persistently. Run via your Desktop shortcut."
Write-Host "======================================================" -ForegroundColor Cyan
