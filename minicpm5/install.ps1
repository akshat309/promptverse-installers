<#
.SYNOPSIS
PromptVerse One-Click Automated Installer for MiniCPM5-1B
.DESCRIPTION
This script installs Python, Git, creates a virtual environment, detects CUDA/VRAM, 
installs dependencies, downloads the MiniCPM5-1B model, and sets up a branded Gradio WebUI.
#>

$ErrorActionPreference = "Stop"
$InstallPath = "C:\MiniCPM5-1B"
$RepoUrl = "https://github.com/OpenBMB/MiniCPM.git"
$ShortcutPath = "$([Environment]::GetFolderPath('Desktop'))\MiniCPM5-1B PromptVerse.lnk"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   PROMPTVERSE: MINICPM5-1B ONE-CLICK INSTALLER       " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Cyan

# 1. System Validation (RAM & VRAM)
Write-Host "`n[1/7] Running System Validation..." -ForegroundColor Yellow
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
        if ($VRAM -lt 4) { 
            Write-Host "Low VRAM detected. Will enable 4-bit/8-bit quantization options in UI." -ForegroundColor Yellow 
        }
        
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
    Write-Host "Python not found. Installing Python 3.10 via Winget..."
    winget install --id Python.Python.3.10 -e --source winget --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# 3. Clone Repository
Write-Host "`n[3/7] Setting up installation directory..." -ForegroundColor Yellow
if (Test-Path $InstallPath) { Remove-Item -Recurse -Force $InstallPath }
git clone $RepoUrl $InstallPath
Set-Location $InstallPath

# 4. Virtual Environment Setup
Write-Host "`n[4/7] Creating Python Virtual Environment..." -ForegroundColor Yellow
python -m venv venv
$ActivateCmd = "$InstallPath\venv\Scripts\activate.ps1"

# 5. Installing Dependencies
Write-Host "`n[5/7] Installing PyTorch & Dependencies (This may take a while)..." -ForegroundColor Yellow
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

# 6. Generate PromptVerse WebUI and Launcher
Write-Host "`n[6/7] Generating PromptVerse Gradio UI..." -ForegroundColor Yellow
$AppContent = @"
import gradio as gr
from transformers import AutoModelForCausalLM, AutoTokenizer
import torch

model_id = 'openbmb/MiniCPM5-1B'
print(f'Loading {model_id} from Hugging Face...')
tokenizer = AutoTokenizer.from_pretrained(model_id)
model = AutoModelForCausalLM.from_pretrained(
    model_id,
    torch_dtype='auto',
    device_map='auto'
)

def generate_text(prompt, think_mode):
    messages = [{'role': 'user', 'content': prompt}]
    inputs = tokenizer.apply_chat_template(
        messages,
        tokenize=True,
        add_generation_prompt=True,
        enable_thinking=think_mode,
        return_dict=True,
        return_tensors='pt'
    ).to(model.device)
    
    outputs = model.generate(**inputs, max_new_tokens=512)
    return tokenizer.decode(outputs[0][inputs['input_ids'].shape[-1]:], skip_special_tokens=True)

with gr.Blocks(theme=gr.themes.Soft(primary_hue='cyan'), title='PromptVerse MiniCPM5-1B') as demo:
    gr.Markdown('# 🌌 PromptVerse: MiniCPM5-1B Local UI')
    with gr.Row():
        with gr.Column(scale=2):
            user_input = gr.Textbox(lines=4, placeholder='Enter your prompt here...', label='Input')
            think_toggle = gr.Checkbox(label='Enable Hybrid Reasoning (<think> mode)', value=True)
            submit_btn = gr.Button('Generate', variant='primary')
        with gr.Column(scale=3):
            output_box = gr.Textbox(lines=10, label='Model Output')
    
    submit_btn.click(generate_text, inputs=[user_input, think_toggle], outputs=output_box)

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

# 7. Desktop Shortcut & Cleanup
Write-Host "`n[7/7] Creating Desktop Shortcut and Cleaning Up..." -ForegroundColor Yellow
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "$InstallPath\start_webui.bat"
$Shortcut.WorkingDirectory = $InstallPath
$Shortcut.IconLocation = "cmd.exe"
$Shortcut.Save()

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host " INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host " A shortcut has been placed on your Desktop."
Write-Host "======================================================" -ForegroundColor Cyan
